# frozen_string_literal: true

# Input and handle IO: stdin shared between Haskell code and the REPL,
# lazy getContents, getArgs, stderr, and GHCi's handle states. The
# expected messages are GHCi 9.6's.

def io_cli(argv, input = '')
  out = RT::FakeIO.new
  err = RT::FakeIO.new
  code = Rhci::CLI.main(argv, stdin: RT::FakeIO.new(input), stdout: out, stderr: err)
  [out.written, err.written, code]
end

def io_session(input, *exprs)
  out = RT::FakeIO.new
  err = RT::FakeIO.new
  s = Rhci::Session.new(stdout: out, stdin: RT::FakeIO.new(input), stderr: err)
  msgs = []
  exprs.each do |e|
    r = s.eval(e)
    msgs << r.message unless r.ok?
  end
  [out.written, err.written, msgs]
end

RT.suite 'input and handles' do
  RT.test 'getLine reads one line without its newline; EOF is an exception' do
    RT.eq ["ba\ndc\n", '', []], io_session("ab\ncd", 'getLine >>= putStrLn . reverse', 'getLine >>= putStrLn . reverse')
    _, _, msgs = io_session('', 'getLine')
    RT.eq ['<stdin>: hGetLine: end of file'], msgs
    _, _, msgs = io_session('', 'getChar')
    RT.eq ['<stdin>: hGetChar: end of file'], msgs
  end

  RT.test 'getChar and isEOF; non-ASCII input is read as characters' do
    RT.eq ["('\\955',False)\nTrue\n", '', []],
          io_session("\u03BB\n", 'getChar >>= \c -> isEOF >>= \e -> print (c, e)', 'getChar >> isEOF >>= print')
  end

  RT.test 'getContents is lazy, then stdin is semi-closed, and closed at its end' do
    out, _, msgs = io_session("ab\ncd", 'getContents >>= \s -> print (take 1 s) >> getLine >>= print')
    RT.eq "\"a\"\n", out
    RT.eq ['<stdin>: hGetLine: illegal operation (handle is semi-closed)'], msgs
    out, _, msgs = io_session('ab', 'getContents >>= print >> getContents >>= print')
    RT.eq "\"ab\"\n", out
    RT.eq ['<stdin>: hGetContents: illegal operation (handle is closed)'], msgs
  end

  RT.test 'the REPL reads the same stdin, after what isEOF looked ahead at' do
    out, err, code = io_cli([], "isEOF\ngetLine\n  1+1\n")
    RT.eq ["rhci> False\nrhci> \"  1+1\"\nrhci> \n", '', 0], [out, err, code]
  end

  RT.test 'stdout is flushed before stderr is written and before stdin is read' do
    log = []
    out = RT::FakeIO.new(log: log, tag: 'out')
    err = RT::FakeIO.new(log: log, tag: 'err')
    s = Rhci::Session.new(stdout: out, stdin: RT::FakeIO.new("x\n"), stderr: err)
    RT.eq :ok, s.eval('putStr "a" >> hPutStr stderr "b" >> putStr "c" >> getLine >>= putStrLn').status
    RT.eq ['out:a', 'err:b', 'out:c', "out:x\n"], log
  end

  RT.test 'handles: show, Eq, buffering as reported by GHCi, wrong direction' do
    out, _, msgs = io_session('', 'print (stdout, stdin == stdout, stderr == stderr)',
                              'hGetBuffering stdout >>= print',
                              'hSetBuffering stdout LineBuffering >> hGetBuffering stdout >>= print',
                              'hGetLine stdout', 'hPutStrLn stdin "x"')
    RT.eq "({handle: <stdout>},False,True)\nNoBuffering\nLineBuffering\n", out
    RT.eq ['<stdout>: hGetLine: illegal operation (handle is not open for reading)',
           '<stdin>: hPutChar: illegal operation (handle is not open for writing)'], msgs
  end

  RT.test 'hPutStrLn stderr, hPrint, getProgName' do
    RT.eq ["\"<interactive>\"\n", "e\n(1,'x')\n", []],
          io_session('', 'hPutStrLn stderr "e" >> hPrint stderr (1, \'x\')', 'getProgName >>= print')
  end

  RT.test '-x: getArgs sees the arguments as Strings' do
    RT.eq ["[\"one\",\"two words\",\"\"]\n", '', 0], io_cli(['-x', 'getArgs >>= print', 'one', 'two words', ''])
    RT.eq ["[]\n", '', 0], io_cli(['-x', 'getArgs >>= print'])
  end

  RT.test '-i applies the expression to stdin, as interact does' do
    RT.eq ["HELLO\nWORLD", '', 0], io_cli(['-i', '-c', 'map toUpper'], "hello\nworld")
    RT.eq ["b\nc\n", '', 0], io_cli(['-i', '-c', 'unlines . sort . lines'], "c\nb\n")
    RT.eq ["2\n", '', 0], io_cli(['-i', '-c', 'length . lines'], "a\nb\n")
    RT.eq ["\ndc", '', 0], io_cli(['-i', '-x', 'putStr . reverse'], "cd\n")
    _, err, code = io_cli(['-i', '-x', 'const getLine'], 'abc')
    RT.eq 1, code
    RT.ok err.include?('semi-closed'), err
  end

  RT.test '-i -c with arguments: stdin comes last' do
    RT.eq ["ab\nab\n", '', 0], io_cli(['-i', '-c', '\n s -> concat (replicate n s)', '2'], "ab\n")
  end

  RT.test '-i output is incremental: a prefix appears before an exception' do
    out, err, code = io_cli(['-i', '-c', 'map (\c -> if c == \'!\' then error "bang" else c)'], 'ab!c')
    RT.eq ['ab', 1], [out, code]
    RT.ok err.include?('bang'), err
  end
end
