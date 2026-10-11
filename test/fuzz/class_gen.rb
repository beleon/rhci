# frozen_string_literal: true

# User class hierarchies (test/fuzz/run.rb --classes): each section declares
# random classes -- methods with and without defaults (some defaults using
# a superclass's method), a superclass chain, a class with two
# superclasses, a method polymorphic in its result (make :: Int -> a), a
# constructor class -- and instances for Int, Bool, Char, lists and Maybe
# (with contexts), pairs and a user type, leaving some instances and
# methods out. Probes call methods at those types, give them literals for
# defaulting to resolve through the user classes (ExtendedDefaultRules),
# use make with and without annotations, hit missing methods and
# instances, and define polymorphic functions over the classes, with :t.
module Fuzz
  class ClassGen
    BASE = %w[Int Bool Char].freeze

    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    def section(n)
      decls, @insts = declarations
      decls + Array.new(n) { probe }
    end

    # A value of type t, as an expression.
    def value(t)
      case t
      when 'Int' then "(#{pick([0, 3, -2, 7])} :: Int)"
      when 'Bool' then pick(%w[True False])
      when 'Char' then pick(["'a'", "'z'", "'0'"])
      when 'U' then pick(['UA', 'UB 2', 'UB (-1)'])
      when '[Int]' then "[#{value('Int')}, #{value('Int')}]"
      when '[Bool]' then "[#{value('Bool')}]"
      when 'Maybe Int' then pick(['Nothing', "Just #{value('Int')}"])
      when 'Maybe Char' then pick(['Nothing', "Just #{value('Char')}"])
      when '(Int, Bool)' then "(#{value('Int')}, #{value('Bool')})"
      else '()'
      end
    end

    TYPES = ['Int', 'Bool', 'Char', 'U', '[Int]', '[Bool]', 'Maybe Int', 'Maybe Char', '(Int, Bool)', '()'].freeze

    def body(arg)
      pick(["length (show #{arg})", '7', "fromEnum (#{arg} == #{arg})", 'negate 3', "length [#{arg}, #{arg}]"])
    end

    def declarations
      out = ['data U = UA | UB Int deriving (Show, Eq)']
      # The hierarchy: Base <- Mid <- Top (Top also needs Show).
      base_default = chance(0.5)
      out << ":{\nclass Base a where\n  size :: a -> Int\n  label :: a -> String\n" \
             "#{base_default ? "  label x = \"b\" ++ show (size x)\n" : ''}:}"
      mid_default = chance(0.6)
      out << ":{\nclass Base a => Mid a where\n  combine :: a -> a -> Int\n" \
             "#{mid_default ? "  combine x y = size x * 10 + size y\n" : ''}:}"
      out << ":{\nclass (Mid a, Show a) => Top a where\n  describe :: a -> String\n  describe x = label x ++ \":\" ++ show x\n:}"
      out << ":{\nclass Make a where\n  make :: Int -> a\n:}"
      out << ":{\nclass Box f where\n  bmap :: (a -> b) -> f a -> f b\n  bsize :: f a -> Int\n  bsize _ = 1\n:}"
      insts = { 'Base' => [], 'Mid' => [], 'Top' => [], 'Make' => [], 'Box' => [] }
      TYPES.each do |t|
        next unless chance(0.7)

        insts['Base'] << t
        ctx = case t
              when '[Int]', '[Bool]' then ['Base a => ', '[a]']
              when 'Maybe Int', 'Maybe Char' then ['Base a => ', 'Maybe a']
              when '(Int, Bool)' then ['(Base a, Base b) => ', '(a, b)']
              else ['', t]
              end
        next if out.any? { |l| l.include?("instance #{ctx[0]}Base (#{ctx[1]})") }

        arg = ctx[1] == '[a]' ? 'xs' : 'x'
        size = case ctx[1]
               when '[a]' then 'sum (map size xs)'
               when 'Maybe a' then 'maybe 0 size x'
               when '(a, b)' then 'size (fst x) + size (snd x)'
               else body('x')
               end
        label = !base_default || chance(0.4) ? "\n  label _ = \"#{t[0]}\"" : ''
        out << ":{\ninstance #{ctx[0]}Base (#{ctx[1]}) where\n  size #{arg} = #{size}#{label}\n:}"
        next unless chance(0.7)

        insts['Mid'] << t
        mctx = ctx[0].gsub('Base', 'Mid')
        comb = !mid_default || chance(0.3) ? "\n  combine x y = size x - size y" : ''
        out << ":{\ninstance #{mctx}Mid (#{ctx[1]}) where#{comb}\n:}"
        if chance(0.5)
          insts['Top'] << t
          tctx = ctx[0].empty? ? '' : "#{ctx[0].gsub('Base', 'Top').sub(' => ', '')} => ".sub('((', '(')
          out << "instance #{tctx}Top (#{ctx[1]})"
        end
      end
      %w[Int Bool U ()].each do |t|
        next unless chance(0.6)

        insts['Make'] << t
        v = { 'Int' => 'n * 2', 'Bool' => 'even n', 'U' => 'if n > 0 then UB n else UA', '()' => '()' }[t]
        out << "instance Make #{t} where make n = #{v}"
      end
      if chance(0.8)
        insts['Box'] << 'Maybe'
        out << ":{\ninstance Box Maybe where\n  bmap = fmap\n  bsize = maybe 0 (const 1)\n:}"
      end
      if chance(0.8)
        insts['Box'] << '[]'
        out << ":{\ninstance Box [] where\n  bmap = map#{chance(0.5) ? "\n  bsize = length" : ''}\n:}"
      end
      [out, insts]
    end

    def probe
      t = pick(TYPES)
      v = value(t)
      case @r.rand(16)
      when 0, 1 then "size #{v}"
      when 2 then "label #{v}"
      when 3 then "combine #{v} #{value(t)}"
      when 4 then "describe #{v}"
      when 5 then "make #{pick([0, 3, -1])} :: #{pick(%w[Int Bool U () Char])}"
      when 6 then pick(['make 3', 'show (make 3)', '[make 1, UA]', 'size (make 2)', 'make 2 == UA', 'make 4 + 1'])
      when 7 then pick(['size 3', 'size 2.5', 'label 7', 'combine 1 2', 'describe 5', 'size []', 'size Nothing',
                        'size (1, True)', "size ('a', 'b')", 'describe [1, 2]', 'size [[True]]'])
      when 8 then "bmap (+ 1) #{pick(['(Just 3)', '[1, 2]', 'Nothing', '[]'])}"
      when 9 then "bsize #{pick(['(Just 3)', '[1, 2, 3]', 'Nothing', '[]', '"abc"', '(Right 3)'])}"
      when 10 then "let f x = size x + combine x x in f #{v}"
      when 11 then "let g x y = (describe x, size y) in g #{v} #{value(pick(TYPES))}"
      when 12 then ":t #{pick(['\\x -> size x + combine x x', 'describe', '\\x -> (label x, make 1 `asTypeOf` x)',
                               'bmap', '\\b -> bsize (bmap show b)', '\\x y -> combine x y + size (Just x)',
                               '\\x -> describe [x]', 'combine', '\\xs -> map size xs', 'make',
                               '\\x -> show (make x) ++ label (make x)'])}"
      when 13 then "map label [#{v}, #{value(t)}]"
      when 14 then "(#{v}, describe #{v})"
      else "sum (map size [#{v}, #{value(t)}]) + combine #{value(t)} #{v}"
      end
    end
  end
end
