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

    # [module source, stdin]
    def program
      @env = []
      @funcs = []
      @cons = (%w[TC TA] + CONS.keys.reject { |c| %w[TC TA].include?(c) }.select { chance(0.5) }).uniq
      out = ['module Main where', ''] + IMPORTS + ['']
      out.concat(Gen::DECLS.reject { |l| l == ':{' || l == ':}' })
      out << ''
      out << "data T = #{@cons.map { |c| CONS[c][0] }.join(' | ')} deriving (Show, Eq, Ord)"
      out << ''
      out.concat(measure_class)
      @r.rand(6..10).times do |i|
        out << ''
        out.concat(function("f#{i}"))
      end
      out << ''
      body, input = main_body
      out.concat(body)
      [out.join("\n") + "\n", input]
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
      kind = pick(%i[guards equations equations recursive case lambda mutual local_poly])
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
