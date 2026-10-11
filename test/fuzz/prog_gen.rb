# frozen_string_literal: true

require_relative 'gen'

# Random whole programs (test/fuzz/progs.rb): a module with a data type, a
# class, functions in the shapes Haskell programs take (equations over
# patterns, guards, where, case, let, recursion, mutual recursion, local
# polymorphic helpers, lambdas), and a `main` that reads stdin and prints.
# Expressions come from Gen, with the variables in scope as leaves and calls
# to functions defined earlier. Every program terminates: functions call
# only earlier ones, and recursion is structural or on a bounded counter.
module Fuzz
  class ProgGen < Gen
    USERT = :usert

    # Constructors the data type T may have: [declaration, field types].
    CONS = {
      'TA' => ['TA Int', [INT]],
      'TB' => ['TB Bool T', [BOOL, USERT]],
      'TC' => ['TC', []],
      'TD' => ['TD { tdx :: Int, tdy :: Maybe Int }', [INT, [:maybe, INT]]],
      'TE' => ['TE T T', [USERT, USERT]],
      'TF' => ['TF String', [STRING]]
    }.freeze

    ARG_TYPES = [INT, INT, STRING, [:list, INT], [:list, INT], BOOL, USERT, [:maybe, INT]].freeze
    RET_TYPES = [INT, INT, BOOL, STRING, [:list, INT], [:maybe, INT], USERT, INTEGER].freeze

    # Partial functions on random data end most programs early; programs
    # use fewer empty lists and smaller indices, so more of main runs.
    def initialize(seed, bottoms: 0.0)
      super
      @empty_rate = 0.08
      @env = []
      @funcs = []
      @cons = []
    end

    # ---- types and leaves ---------------------------------------------------------

    def hs_type(t)
      t == USERT ? 'T' : super
    end

    def leaf(t)
      return usert_leaf if t == USERT

      vars = @env.select { |_, vt| vt == t }
      return pick(vars)[0] if !vars.empty? && chance(0.6)

      super
    end

    def expr(t, d)
      return usert_expr(d) if t == USERT
      if d.positive? && chance(0.2)
        fs = @funcs.select { |f| f[:ret] == t }
        unless fs.empty?
          f = pick(fs)
          return "#{f[:name]} #{f[:args].map { |a| sub(a, d) }.join(' ')}"
        end
      end
      if t == INT && d.positive? && chance(0.08)
        return case @r.rand(4)
               when 0 then "#{sub(INT, d)} #{pick(['.&.', '.|.', '`xor`'])} #{sub(INT, d)}"
               when 1 then "shiftL #{sub(INT, d)} (#{@r.rand(0..5)} :: Int)"
               when 2 then "popCount #{sub(INT, d)}"
               else "fromInteger (numerator (#{sub(INTEGER, d)} % (1 + abs #{sub(INTEGER, d)})))"
               end
      end
      super
    end

    def usert_leaf
      flat = @cons.reject { |c| CONS[c][1].include?(USERT) }
      c = pick(flat)
      fields = CONS[c][1].map { |t| super_leaf(t) }
      return c if fields.empty?

      c == 'TD' ? "(TD { tdx = #{fields[0]}, tdy = #{fields[1]} })" : "(#{c} #{fields.join(' ')})"
    end

    def super_leaf(t)
      t == USERT ? usert_leaf : leaf(t)
    end

    def usert_expr(d)
      return usert_leaf if d <= 0 || chance(0.3)

      c = pick(@cons)
      fields = CONS[c][1].map { |t| sub(t, d) }
      return c if fields.empty?

      c == 'TD' ? "TD { tdx = #{fields[0]}, tdy = #{fields[1]} }" : "#{c} #{fields.join(' ')}"
    end

    def small_int
      "(#{@r.rand(0..2)} :: Int)"
    end

    def with_env(vars)
      @env.concat(vars)
      yield
    ensure
      vars.length.times { @env.pop }
    end

    # ---- the program ------------------------------------------------------------

    IMPORTS = ['import Data.List', 'import Data.Char', 'import Data.Maybe', 'import qualified Data.Map as M',
               'import qualified Data.Set as S', 'import Text.Printf', 'import Data.IORef', 'import Data.Bits',
               'import Data.Ratio', 'import Control.Monad', 'import System.IO'].freeze

    # [{file name => source}, stdin]: one module, or (half the time) three.
    def program
      @env = []
      @funcs = []
      @cons = (%w[TC TA] + CONS.keys.reject { |c| %w[TC TA].include?(c) }.select { chance(0.5) }).uniq
      return multi_module_program if chance(0.5)

      out = ['module Main where', ''] + IMPORTS + [''] + type_decls
      @r.rand(6..10).times do |i|
        out << ''
        out.concat(function("f#{i}"))
      end
      out << ''
      body, input = main_body
      out.concat(body)
      [{ 'Main.hs' => out.join("\n") + "\n" }, input]
    end

    def type_decls
      Gen::DECLS.reject { |l| l == ':{' || l == ':}' } +
        ['', "data T = #{@cons.map { |c| CONS[c][0] }.join(' | ')} deriving (Show, Eq, Ord)", ''] + measure_class +
        [''] + MONAD_DECLS
    end

    # A hand-rolled State monad and a Foldable container: user instances of
    # Functor, Applicative, Monad and Foldable.
    MONAD_DECLS = [
      'newtype St s a = St { runSt :: s -> (a, s) }',
      '',
      'instance Functor (St s) where',
      "  fmap f (St g) = St (\\s -> let (a, s') = g s in (f a, s'))",
      '',
      'instance Applicative (St s) where',
      '  pure a = St (\\s -> (a, s))',
      '  St f <*> St g = St (\\s -> let { (h, s1) = f s; (a, s2) = g s1 } in (h a, s2))',
      '',
      'instance Monad (St s) where',
      '  St g >>= k = St (\\s -> let (a, s1) = g s in runSt (k a) s1)',
      '',
      'getSt :: St s s',
      'getSt = St (\\s -> (s, s))',
      '',
      'putSt :: s -> St s ()',
      'putSt s = St (\\_ -> ((), s))',
      '',
      'modifySt :: (s -> s) -> St s ()',
      'modifySt f = St (\\s -> ((), f s))',
      '',
      'data Bag a = NoBag | One a | Both a a deriving (Show, Eq)',
      '',
      'instance Functor Bag where',
      '  fmap _ NoBag = NoBag',
      '  fmap f (One a) = One (f a)',
      '  fmap f (Both a b) = Both (f a) (f b)',
      '',
      'instance Foldable Bag where',
      '  foldr _ z NoBag = z',
      '  foldr f z (One a) = f a z',
      '  foldr f z (Both a b) = f a (f b z)'
    ].freeze

    TYPE_EXPORTS = 'T(..), Measure(..), Shape(..), R(..), V(..), Describe(..), Rank(..), Box(..), St(..), ' \
                   'getSt, putSt, modifySt, Bag(..)'

    # Types (the declarations), Lib (functions, some exported) and Main (the
    # rest, and main), importing Lib qualified, by a list, hiding some, or
    # whole; Main may reuse the name of a Lib function it cannot see.
    def multi_module_program
      header = chance(0.5) ? 'module Types where' : "module Types (#{TYPE_EXPORTS}) where"
      types = [header, ''] + type_decls
      first = @funcs.length
      lib = []
      @r.rand(3..6).times do |i|
        lib << ''
        lib.concat(function("f#{i}"))
      end
      # Every function Lib defines (a mutual pair defines two).
      lib_names = @funcs[first..-1].map { |f| f[:name] }.uniq
      exported = lib_names.select { chance(0.7) }
      exported = [lib_names.last] if exported.empty?
      lib_src = ["module Lib (#{exported.join(', ')}) where", '', 'import Types'] + IMPORTS + lib
      style = pick(%i[qualified list hiding whole])
      visible, import_line = case style
                             when :qualified then [exported.to_h { |n| [n, "L.#{n}"] }, 'import qualified Lib as L']
                             when :list
                               some = exported.select { chance(0.6) }
                               some = [exported.first] if some.empty?
                               [some.to_h { |n| [n, n] }, "import Lib (#{some.join(', ')})"]
                             when :hiding
                               hidden = exported.select { chance(0.3) }
                               [(exported - hidden).to_h { |n| [n, n] },
                                hidden.empty? ? 'import Lib' : "import Lib hiding (#{hidden.join(', ')})"]
                             else [exported.to_h { |n| [n, n] }, 'import Lib']
                             end
      @funcs = @funcs.filter_map do |f|
        next f unless lib_names.include?(f[:name])

        visible.key?(f[:name]) ? f.merge(name: visible[f[:name]]) : nil
      end
      # Names Main may define again: Lib's that are not in scope unqualified.
      free = lib_names.reject { |n| visible[n] == n }
      main = ['module Main where', '', 'import Types', import_line] + IMPORTS
      @r.rand(2..4).times do |i|
        name = !free.empty? && chance(0.4) ? free.delete(pick(free)) : "m#{i}"
        main << ''
        main.concat(function(name))
      end
      main << ''
      body, input = main_body
      main.concat(body)
      [{ 'Types.hs' => types.join("\n") + "\n", 'Lib.hs' => lib_src.join("\n") + "\n",
         'Main.hs' => main.join("\n") + "\n" }, input]
    end

    def measure_class
      eqs = @cons.map do |c|
        fields = CONS[c][1]
        vars = fields.each_with_index.map { |_, i| "v#{i}" }
        rhs = fields.each_with_index.map do |t, i|
          case t
          when INT then vars[i]
          when BOOL then "fromEnum #{vars[i]}"
          when USERT then "measure #{vars[i]}"
          when STRING then "length #{vars[i]}"
          else "maybe 0 id #{vars[i]}"
          end
        end
        pat = vars.empty? ? c : (c == 'TD' ? "(TD #{vars.join(' ')})" : "(#{c} #{vars.join(' ')})")
        "  measure #{pat} = #{rhs.empty? ? @r.rand(0..9) : rhs.join(' + ')}"
      end
      @funcs << { name: 'measure', args: [USERT], ret: INT }
      @funcs << { name: 'measure', args: [[:list, INT]], ret: INT }
      @funcs << { name: 'mname', args: [USERT], ret: STRING }
      @funcs << { name: 'mname', args: [BOOL], ret: STRING }
      ['class Measure a where', '  measure :: a -> Int', '  mname :: a -> String',
       '  mname x = "m" ++ show (measure x)', '', 'instance Measure T where'] + eqs +
        ['', 'instance Measure Int where measure = abs', '',
         'instance Measure Bool where { measure b = if b then 1 else 0; mname b = if b then "T" else "F" }', '',
         'instance Measure a => Measure [a] where', '  measure = sum . map measure',
         '  mname xs = concatMap mname xs']
    end

    # ---- functions --------------------------------------------------------------

    def function(name)
      kind = pick(%i[guards equations equations recursive case lambda mutual local_poly state maybe_do list_do bag
                     poly record])
      return send_template(kind, name) if %i[state maybe_do list_do bag poly record].include?(kind)

      args = Array.new(@r.rand(1..2)) { pick(ARG_TYPES) }
      ret = pick(RET_TYPES)
      lines = case kind
              when :guards then guards_fn(name, args, ret)
              when :equations then equations_fn(name, args, ret, recursive: false)
              when :recursive then equations_fn(name, args, ret, recursive: true)
              when :case then case_fn(name, args, ret)
              when :lambda then lambda_fn(name)
              when :mutual then return mutual_fns(name)
              else local_poly_fn(name, args, ret)
              end
      sig = lines.shift
      @funcs << sig[:info]
      (chance(0.15) && kind != :lambda ? [] : ["#{name} :: #{sig[:text]}"]) + lines
    end

    # The templates for monads, user Functor/Foldable instances, class-
    # polymorphic functions and record updates; each registers the function
    # at ordinary types, so expressions can call it.
    def send_template(kind, name)
      case kind
      when :state then state_fn(name)
      when :maybe_do then maybe_do_fn(name)
      when :list_do then list_do_fn(name)
      when :bag then bag_fn(name)
      when :poly then poly_fn(name)
      else @cons.include?('TD') ? record_fn(name) : bag_fn(name)
      end
    end

    def state_fn(name)
      lines = ["#{name} :: [Int] -> Int", "#{name} xs = fst (runSt (go xs) #{@r.rand(0..9)})", '  where']
      cond = with_env([['x', INT]]) { expr(BOOL, 2) }
      step = with_env([['x', INT]]) { expr(INT, 2) }
      put = with_env([['s', INT]]) { expr(INT, 2) }
      ret = with_env([['s', INT]]) { expr(INT, 2) }
      lines.concat(['    go :: [Int] -> St Int Int', '    go ys = do',
                    "      forM_ ys (\\x -> when (#{cond}) (modifySt (+ (#{step}))))",
                    '      s <- getSt', "      putSt (#{put})", "      fmap (+ 1) (return (#{ret}))"])
      @funcs << { name: name, args: [[:list, INT]], ret: INT }
      lines
    end

    def maybe_do_fn(name)
      lines = ["#{name} :: Int -> Maybe Int", "#{name} n = do"]
      with_env([['n', INT]]) do
        lines << "  a <- #{sub([:maybe, INT], 2)}"
        with_env([['a', INT]]) do
          lines << "  guard (#{expr(BOOL, 2)})"
          lines << "  b <- #{chance(0.5) ? "Just (#{expr(INT, 2)})" : 'Nothing'}"
          with_env([['b', INT]]) { lines << "  return (#{expr(INT, 2)})" }
        end
      end
      @funcs << { name: name, args: [INT], ret: [:maybe, INT] }
      lines
    end

    def list_do_fn(name)
      lines = ["#{name} :: [Int] -> [Int]", "#{name} xs = do", '  x <- xs']
      with_env([['xs', [:list, INT]], ['x', INT]]) do
        lines << "  y <- [x, x + 1, #{expr(INT, 1)}]"
        with_env([['y', INT]]) do
          lines << "  guard (#{expr(BOOL, 2)})"
          lines << "  return (#{expr(INT, 2)})"
        end
      end
      @funcs << { name: name, args: [[:list, INT]], ret: [:list, INT] }
      lines
    end

    def bag_fn(name)
      lines = ["#{name} :: [Int] -> Int", "#{name} xs = sum b' + length b' + foldr (\\v acc -> v - acc) 0 b'",
               '  where', '    b = case xs of { [] -> NoBag; [a] -> One a; (a : c : _) -> Both a c }']
      lines << "    b' = fmap (#{with_env([['v', INT]]) { "\\v -> #{expr(INT, 2)}" }}) b"
      @funcs << { name: name, args: [[:list, INT]], ret: INT }
      lines
    end

    # Class-polymorphic, called at several types.
    def poly_fn(name)
      if chance(0.5)
        lines = ["#{name} :: (Measure a, Show a) => [a] -> String",
                 "#{name} vs = concatMap (\\v -> show v ++ mname v) vs ++ show (measure vs)"]
        [[:list, INT], [:list, BOOL]].each { |t| @funcs << { name: name, args: [t], ret: STRING } }
      else
        lines = ["#{name} :: Ord a => a -> a -> [a]", "#{name} p q = if p < q then [p, q, max p q] else [min p q]"]
        @funcs << { name: name, args: [INT, INT], ret: [:list, INT] }
        @funcs << { name: name, args: [CHAR, CHAR], ret: STRING }
      end
      lines
    end

    def record_fn(name)
      lines = ["#{name} :: T -> T", "#{name} t = case t of"]
      with_env([['t', USERT]]) do
        lines << "  TD {} -> t { tdx = tdx t + #{sub(INT, 2)}, tdy = fmap (+ 1) (tdy t) }"
        lines << "  _ -> #{chance(0.5) ? 't' : 'TD { tdx = 0, tdy = Nothing }'}"
      end
      @funcs << { name: name, args: [USERT], ret: USERT }
      lines
    end

    def signature(name, args, ret)
      { info: { name: name, args: args, ret: ret }, text: (args + [ret]).map { |t| paren_fn(t) }.join(' -> ') }
    end

    def paren_fn(t)
      hs_type(t)
    end

    def arg_vars(args, from = 0)
      args.each_with_index.map { |t, i| ["a#{i + from}", t] }
    end

    def guards_fn(name, args, ret)
      vars = arg_vars(args)
      lines = [signature(name, args, ret), "#{name} #{vars.map(&:first).join(' ')}"]
      with_env(vars) do
        w_t = pick([INT, BOOL, STRING, [:list, INT]])
        w = expr(w_t, 2)
        with_env([['w', w_t]]) do
          local = { name: 'lk', args: [INT], ret: INT }
          lk = with_env([['z', INT]]) { expr(INT, 2) }
          @funcs << local
          @r.rand(1..2).times { lines << "  | #{expr(BOOL, 2)} = #{expr(ret, 3)}" }
          lines << "  | otherwise = #{expr(ret, 3)}"
          @funcs.delete(local)
          lines << '  where' << "    w = #{w}" << '    lk :: Int -> Int' << "    lk z = #{lk}"
        end
      end
      lines
    end

    # One equation per shape of the first argument; recursive ones call
    # themselves on a smaller first argument (r: the call's result).
    def equations_fn(name, args, ret, recursive:)
      first = args[0]
      rest = arg_vars(args[1..-1], 1)
      rest_names = rest.map(&:first).join(' ')
      lines = [signature(name, args, ret)]
      self_call = ->(smaller) { "#{name} #{smaller} #{rest_names}".strip }
      eq = lambda do |pat, vars, smaller = nil|
        with_env(vars + rest) do
          body = if recursive && smaller
                   with_env([['r', ret]]) { "let r = #{self_call.call(smaller)} in #{expr(ret, 3)}" }
                 else
                   expr(ret, 3)
                 end
          lines << "#{name} #{pat} #{rest_names}".rstrip + " = #{body}"
        end
      end
      case first
      when INT
        if recursive
          with_env([['n', INT]] + rest) do
            lines << "#{name} n #{rest_names}".rstrip
            lines << "  | n <= 0 || n > 25 = #{expr(ret, 2)}"
            with_env([['r', ret]]) { lines << "  | otherwise = let r = #{self_call.call('(n - 1)')} in #{expr(ret, 3)}" }
          end
        else
          eq.call('0', [])
          eq.call('1', []) if chance(0.5)
          eq.call('n', [['n', INT]])
        end
      when STRING
        eq.call('""', [])
        eq.call("(c : cs)", [['c', CHAR], ['cs', STRING]], 'cs')
      when [:list, INT]
        eq.call('[]', [])
        if chance(0.5)
          eq.call('[x]', [['x', INT]])
          eq.call('whole@(x : y : more)', [['x', INT], ['y', INT], ['more', [:list, INT]], ['whole', [:list, INT]]], 'more')
        else
          eq.call('(x : xs)', [['x', INT], ['xs', [:list, INT]]], 'xs')
        end
      when BOOL
        eq.call('True', [])
        eq.call('False', [])
      when [:maybe, INT]
        eq.call('Nothing', [])
        eq.call('(Just v)', [['v', INT]])
      else # USERT
        @cons.each do |c|
          fields = CONS[c][1]
          vars = fields.each_with_index.map { |t, i| ["p#{i}", t] }
          pat = vars.empty? ? c : "(#{c} #{vars.map(&:first).join(' ')})"
          smaller = vars.find { |_, t| t == USERT }&.first
          eq.call(pat, vars, smaller)
        end
      end
      lines
    end

    def case_fn(name, args, ret)
      vars = arg_vars(args)
      lines = [signature(name, args, ret), "#{name} #{vars.map(&:first).join(' ')} ="]
      with_env(vars) do
        kind = pick([INT, [:maybe, INT], [:list, INT]])
        lines << "  case #{expr(kind, 2)} of"
        case kind
        when INT
          lines << "    0 -> #{expr(ret, 2)}"
          with_env([['k', INT]]) do
            lines << "    k | #{expr(BOOL, 2)} -> #{expr(ret, 2)}"
            lines << "      | otherwise -> let m = #{expr(INT, 2)} in #{with_env([['m', INT]]) { expr(ret, 2) }}"
          end
        when [:maybe, INT]
          lines << "    Nothing -> #{expr(ret, 2)}"
          with_env([['j', INT]]) { lines << "    Just j -> #{expr(ret, 2)}" }
        else
          lines << "    [] -> #{expr(ret, 2)}"
          with_env([['h', INT], ['t', [:list, INT]]]) { lines << "    (h : t) -> #{expr(ret, 2)}" }
        end
      end
      lines
    end

    def lambda_fn(name)
      e = pick([INT, CHAR])
      t = e == INT ? [:list, INT] : STRING
      body = with_env([['x', e]]) { "map (\\x -> #{expr(e, 2)}) . filter (\\x -> #{expr(BOOL, 2)})" }
      [signature(name, [t], t), "#{name} = #{body}"]
    end

    def mutual_fns(name)
      other = "#{name}m"
      ret = pick([INT, BOOL])
      lines = ["#{name} :: Int -> #{hs_type(ret)}", "#{name} n", "  | n <= 0 || n > 25 = #{expr(ret, 2)}"]
      with_env([['n', INT], ['r', ret]]) { lines << "  | otherwise = let r = #{other} (n - 1) in #{expr(ret, 2)}" }
      lines << "#{other} :: Int -> #{hs_type(ret)}" << "#{other} n" << "  | n <= 1 || n > 25 = #{expr(ret, 2)}"
      with_env([['n', INT], ['r', ret]]) { lines << "  | otherwise = let r = #{name} (n - 2) in #{expr(ret, 2)}" }
      # Registered only now: neither body calls them with an arbitrary argument.
      @funcs << { name: name, args: [INT], ret: ret } << { name: other, args: [INT], ret: ret }
      lines
    end

    # A local helper without a signature, used at two types (let
    # polymorphism), and a local pattern binding (the monomorphism
    # restriction does not apply to its use at one type).
    def local_poly_fn(name, args, ret)
      vars = arg_vars(args)
      lines = [signature(name, args, ret), "#{name} #{vars.map(&:first).join(' ')} = pick2 (dup a0) (dup b)"]
      with_env(vars) do
        lines << '  where'
        lines << '    dup v = (v, v)'
        lines << "    b = #{expr(BOOL, 2)}"
        with_env([['p', args[0]], ['q', BOOL]]) { lines << "    pick2 (p, _) (_, q) = #{expr(ret, 3)}" }
      end
      lines
    end

    # ---- main -----------------------------------------------------------------

    def main_body
      lines = ['main :: IO ()', 'main = do', '  ref <- newIORef (0 :: Int)']
      input = random_input
      env = []
      tail_stmt = nil
      case @r.rand(6)
      when 0
        lines << '  contents <- getContents' << '  let ls = lines contents'
        lines << "  mapM_ (\\l -> putStrLn (#{with_env([['l', STRING]]) { expr(STRING, 2) }})) ls"
        env << ['contents', STRING] << ['ls', [:list, STRING]]
      when 1
        lines << '  n <- readLn :: IO Int'
        env << ['n', INT]
      when 2
        lines << '  l1 <- getLine' << '  l2 <- getLine'
        env << ['l1', STRING] << ['l2', STRING]
      when 3
        lines << '  eof <- isEOF'
        lines << '  if eof then putStrLn "none" else getLine >>= putStrLn . reverse'
      when 4
        tail_stmt = "  interact (\\s -> (#{with_env([['s', STRING]]) { expr(STRING, 2) }}) ++ \"\\n\")"
      end
      with_env(env) do
        @r.rand(4..8).times do
          lines << case @r.rand(6)
                   when 0 then "  mapM_ print [#{Array.new(@r.rand(1..3)) { expr(INT, 3) }.join(', ')}]"
                   when 1 then "  modifyIORef ref (+ #{sub(INT, 3)})"
                   when 2 then "  when (#{expr(BOOL, 2)}) (putStrLn #{sub(STRING, 2)})"
                   when 3 then "  forM_ [1 .. 3 :: Int] (\\i -> print (#{with_env([['i', INT]]) { expr(pick(RET_TYPES), 3) }}))"
                   else "  print (#{expr(pick(RET_TYPES + [USERT, [:list, BOOL]]), 3)})"
                   end
        end
      end
      lines << '  readIORef ref >>= print'
      lines << tail_stmt if tail_stmt
      [lines, input]
    end

    def random_input
      lines = Array.new(chance(0.15) ? @r.rand(0..1) : @r.rand(2..4)) do
        chance(0.6) ? pick(['12', '-3', ' 7', '0', '42']) : pick(['hello world', '', 'x', '3 4 5', 'λ'])
      end
      text = lines.join("\n")
      text += "\n" if !lines.empty? && chance(0.8)
      text
    end
  end
end
