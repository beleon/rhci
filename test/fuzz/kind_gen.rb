# frozen_string_literal: true

# Kinds (test/fuzz/run.rb --kinds): random declarations whose parameters
# are used at different kinds -- as a plain field, applied to a type
# (f a), applied to a type constructor (t Maybe), in functions, not at all
# (a phantom) -- plus newtypes, synonyms and classes over them; probes ask
# :k of them, of partial and over-saturated applications, of applications
# at the wrong kind, and of base types and classes.
module Fuzz
  class KindGen
    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    # Field shapes over parameters p (of which a field uses some).
    FIELDS = ['%a', '(%f %a)', '(%f Int)', '(%a -> %b)', '[%a]', '(Maybe %a)', '(%t Maybe)', '(%f (%f %a))',
              '(%a, %b)', '(Either %a %b)', '(%f %a %b)', 'Int'].freeze

    def declaration(i)
      params = %w[a b f t].first(@r.rand(1..4)).shuffle(random: @r)
      fields = Array.new(@r.rand(1..3)) do
        pick(FIELDS).gsub('%a', params[0]).gsub('%b', params[1] || params[0]).gsub('%f', params[2] || params[0])
                    .gsub('%t', params[3] || params[0])
      end
      kw = chance(0.2) ? 'newtype' : 'data'
      fields = [fields[0]] if kw == 'newtype'
      "#{kw} K#{i} #{params.join(' ')} = K#{i} #{fields.join(' ')}"
    end

    def section(n)
      @types = []
      out = []
      @r.rand(2..4).times do |i|
        out << declaration(i + 1)
        @types << "K#{i + 1}"
      end
      out << 'type Syn f = f Int' if chance(0.5)
      out << ":{\nclass Wrap w where\n  wrap :: a -> w a\n:}" if chance(0.5)
      out << ":{\nclass Lift t where\n  lift' :: m a -> t m a\n:}" if chance(0.4)
      out + Array.new(n) { probe }
    end

    ARGS = %w[Int Maybe [] Either (Either\ Int) (,) IO K1 (K1\ Int) (->) Bool].freeze
    BASE = %w[Maybe Either (Either\ Int) [] (,) (,,) (->) ((->)\ Int) IO Int String Functor Monad Show Eq Foldable
              Traversable Num Ord Applicative Monoid Semigroup M.Map S.Set (M.Map\ Int) Wrap Lift Syn (Syn\ Maybe)
              Ordering ()].freeze

    def probe
      case @r.rand(5)
      when 0, 1 then ":k #{pick(@types)}"
      when 2 then ":k #{pick(@types)} #{Array.new(@r.rand(1..3)) { pick(ARGS) }.join(' ')}"
      when 3 then ":k #{pick(BASE)}"
      else ":k #{pick(BASE)} #{pick(ARGS)}"
      end
    end
  end
end
