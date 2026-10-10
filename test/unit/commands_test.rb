# frozen_string_literal: true

# :info and :kind, imports, and the Session's file options. Semantics
# against GHCi are in the oracle; these pin rhci's own output and API.

def cmd_session(*inputs, **opts)
  out = RT::FakeIO.new
  s = Rhci::Session.new(stdout: out, stderr: out, **opts)
  results = inputs.map do |i|
    before = out.written.length
    r = s.eval(i)
    [r.status, out.written[before..-1], r.message]
  end
  results
end

RT.suite ':info, :kind and imports' do
  RT.test ':info shows a data type with its instances, a class with its methods' do
    (status, text, _), = cmd_session(':i Maybe')
    RT.eq :ok, status
    lines = text.split("\n")
    RT.eq 'data Maybe a = Nothing | Just a', lines[0]
    RT.ok lines.include?('instance Functor Maybe'), text
    RT.ok lines.include?('instance Show a => Show (Maybe a)'), text
    (_, text, _), = cmd_session(':info Functor')
    RT.ok text.start_with?("class Functor f where\n  fmap :: (a -> b) -> f a -> f b\n"), text
    RT.ok text.include?('instance Functor IO'), text
    RT.ok !text.include?('StateL'), 'helper types are not shown'
  end

  RT.test ':info on a value, a user type, and a name not in scope' do
    rs = cmd_session(':i map', 'data P = P { px :: Int, py :: !Double }', ':i P', ':i nothere')
    RT.eq "map :: (a -> b) -> [a] -> [b]\n", rs[0][1]
    RT.eq 'data P = P {px :: Int, py :: !Double}', rs[2][1].split("\n")[0]
    RT.eq :scope_error, rs[3][0]
  end

  RT.test ':kind of type constructors, applications, and qualified names' do
    rs = cmd_session(':k Maybe', ':k Either Int', ':k Int -> Int', 'import qualified Data.Map as M', ':k M.Map',
                     ':k Functor', ':k Foo')
    RT.eq ["Maybe :: * -> *\n", "Either Int :: * -> *\n", "Int -> Int :: *\n", '', "M.Map :: * -> * -> *\n",
           "Functor :: (* -> *) -> Constraint\n"], rs[0, 6].map { |r| r[1] }
    RT.eq :scope_error, rs[6][0]
  end

  RT.test 'qualified imports with aliases; unknown modules and items are errors' do
    rs = cmd_session('import qualified Data.Map as M', 'M.toList (M.fromList [(2, "b"), (1, "a")])',
                     'import Data.Set (Set, member)', 'member 3 (Data.Set.fromList [1, 2, 3])', # lint:ok (Haskell)
                     'fromList [1]', 'import Data.Nope', 'import Data.Map (nothere)')
    RT.eq "[(1,\"a\"),(2,\"b\")]\n", rs[1][1]
    RT.eq "True\n", rs[3][1]
    RT.eq :scope_error, rs[4][0], 'Data.Set.fromList was not imported unqualified' # lint:ok (Haskell)
    RT.eq :compile_error, rs[5][0]
    RT.eq :compile_error, rs[6][0]
  end
end

RT.suite 'files' do
  RT.test 'files: false refuses readFile, writeFile and appendFile' do
    rs = cmd_session('readFile "x"', 'writeFile "x" "y"', 'appendFile "x" "y"', files: false)
    RT.eq %i[exception exception exception], rs.map { |r| r[0] }
    RT.eq 'x: openFile: permission denied (file access is disabled)', rs[0][2]
    RT.eq 'x: withFile: permission denied (file access is disabled)', rs[1][2]
  end

  unless Rhci::Shim::MRUBY
    require 'tmpdir' # lint:ok (CRuby only)

    RT.test 'relative file names resolve in the session cwd' do
      Dir.mktmpdir('rhci-cwd') do |dir|
        rs = cmd_session('writeFile "f.txt" "in cwd"', 'readFile "f.txt"', cwd: dir)
        RT.eq "\"in cwd\"\n", rs[1][1]
        RT.eq 'in cwd', File.read(File.join(dir, 'f.txt'))
      end
    end
  end
end
