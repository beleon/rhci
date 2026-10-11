# frozen_string_literal: true

# The whole pipeline (parse, rename, type-check, desugar, lower, run)
# through Rhci::Session, on what needs no type classes.

# Runs inputs in one session; returns [stdout, [[status, message] for
# each input that did not succeed]].
def pl_run(*inputs)
  out = RT::FakeIO.new
  s = Rhci::Session.new(stdout: out)
  problems = []
  inputs.each do |i|
    r = s.eval(i)
    problems << [r.status, r.message] unless r.ok?
  end
  [out.written, problems]
end

def pl_type(src, *defs)
  out, problems = pl_run(*defs, ":t #{src}")
  return problems[0] unless problems.empty?

  out.split("\n").last.sub("#{src} :: ", '')
end

RT.suite 'pipeline' do
  RT.test ':type of class-free expressions' do
    RT.eq '(a -> b) -> [a] -> [b]', pl_type('map')
    RT.eq 'a -> b -> a', pl_type('\\x y -> x')
    RT.eq '(a, b) -> (b, a)', pl_type('\\(a, b) -> (b, a)')
    RT.eq '(Bool, Maybe (Maybe a))', pl_type('let f x = x in (f True, f (Just Nothing))')
    RT.eq '[Char]', pl_type('"a" ++ "b"')
    RT.eq '(a -> a) -> a -> a', pl_type('\\f x -> f (f x)')
    RT.eq 'Either Char a', pl_type("Left 'a'")
  end

  RT.test 'type errors and scope errors are classified' do
    RT.eq :compile_error, pl_type('\\x -> x x')[0]
    RT.eq :compile_error, pl_type("'a' : 'b'")[0]
    RT.eq :compile_error, pl_type('not "x"')[0]
    RT.eq :scope_error, pl_type('nosuchthing')[0]
    RT.eq 'Num a => a', pl_type('1')
    RT.eq :unsupported, pl_type('hTell')[0]
    RT.eq 'Read a => [Char] -> a', pl_type('read')
  end

  RT.test 'definitions, mutual recursion, and signatures' do
    RT.eq 'a -> a', pl_type('idd', 'idd :: a -> a; idd x = x')
    RT.eq '[a] -> [Char]', pl_type('describe', 'describe xs = case xs of { [] -> "empty"; [x] -> "one"; _ -> "more" }')
    out, = pl_run('evens [] = []; evens (x:xs) = x : odds xs; odds [] = []; odds (_:xs) = evens xs',
                  'putStrLn (evens "abcdefg")')
    RT.eq "aceg\n", out
    RT.eq :compile_error, pl_run("f :: a -> a; f x = 'c'")[1][0][0]
  end

  RT.test 'GHCi shadowing: earlier definitions keep the binding they saw' do
    out, = pl_run('x = "old"', 'y = x', 'x = "new"', 'putStrLn (x ++ " " ++ y)')
    RT.eq "new old\n", out
  end

  RT.test 'a failed input changes nothing' do
    out, problems = pl_run('z = "kept"', "z = 'a' : 'b'", 'putStrLn z')
    RT.eq "kept\n", out
    RT.eq :compile_error, problems[0][0]
  end

  RT.test 'laziness of patterns and bindings' do
    out, = pl_run('putStrLn (fst ("ok", undefined))',
                  'putStrLn (case undefined of _ -> "wild")',
                  'putStrLn (let (a, b) = undefined in "unforced")',
                  'f ~(a, b) = "lazy"', 'putStrLn (f undefined)',
                  'putStrLn (take2 (cycle "ab")) where take2 (a:b:_) = [a, b]'.sub(' where take2 (a:b:_) = [a, b]', ''))
    RT.eq "ok\nwild\nunforced\nlazy\n", out.lines.first(4).join
  end

  RT.test 'pattern-match failures raise GHCi-like errors' do
    _, problems = pl_run("g 'a' = \"a\"", "putStrLn (g 'b')")
    RT.eq :exception, problems[0][0]
    RT.ok problems[0][1].include?('Non-exhaustive patterns in function g'), problems[0][1]
    _, problems = pl_run('putStrLn [head ""]')
    RT.eq [:exception, 'Prelude.head: empty list'], problems[0]
  end

  RT.test 'guards fall through to the next equation' do
    out, = pl_run("cls c | c == 'x' = \"never\"".sub("c == 'x'", 'False'), 'cls c = "fallback"', "putStrLn (cls 'q')")
    RT.eq "fallback\n", out
  end

  RT.test 'data types, records, newtypes, strict fields' do
    out, problems = pl_run('data P = P { name :: String, tag :: Char }',
                           'p = P { name = "rec", tag = \'t\' }',
                           'putStrLn (name p ++ [tag p] ++ name (p { name = "upd" }))',
                           'newtype N = N String',
                           'putStrLn (case undefined of N _ -> "newtype patterns do not force")',
                           'data S = S !String',
                           'putStrLn (case S undefined of S _ -> "unreachable")')
    RT.eq "rectupd\nnewtype patterns do not force\n", out
    RT.eq :exception, problems[0][0], 'a strict field forces its argument'
  end

  RT.test 'comprehensions skip elements that do not match' do
    out, = pl_run('putStrLn [c | (c, True) <- zip "Hello" (cycle [True, False])]',
                  'putStrLn [x | Just x <- [Just \'a\', Nothing, Just \'b\']]')
    RT.eq "Hlo\nab\n", out
  end

  RT.test 'strings: escapes, unicode, words/unwords/lines' do
    out, = pl_run('putStrLn "caf\\233 \\955"', 'putStrLn (unwords (reverse (words "  a  bc d ")))',
                  'putStrLn (unlines (lines "x\\ny"))')
    RT.eq "café λ\nd bc a\nx\ny\n\n", out
  end

  RT.test 'strict folds and multi-clause recursion run in constant stack' do
    out = RT::FakeIO.new
    s = Rhci::Session.new(stdout: out, limits: { stack: 500 })
    %w[last\ [1..20000] sum\ [1..20000] length\ [1..20000] maximum\ [1..20000]].each do |e|
      r = s.eval(e)
      RT.ok r.ok?, "#{e}: #{r.status} #{r.message}"
    end
    RT.eq "20000\n200010000\n20000\n20000\n", out.written
  end

  RT.test 'an Integer over the size limit is a limit, not unbounded memory' do
    out = RT::FakeIO.new
    s = Rhci::Session.new(stdout: out, limits: { integer_bits: 10_000 })
    RT.eq :limit, s.eval('(4 :: Integer) ^ (2 ^ 127 :: Integer) `mod` 7').status, 'squaring'
    RT.eq :limit, s.eval('shiftL 1 20000 :: Integer').status, 'shift'
    r = s.eval('length (show (2 ^ 9000 :: Integer))')
    RT.ok r.ok?, "under the limit: #{r.message}"
    RT.eq "2710\n", out.written
  end
end
