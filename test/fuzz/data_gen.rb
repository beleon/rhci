# frozen_string_literal: true

# Random user data types (test/fuzz/run.rb --datatypes). Each section
# declares a few types -- nullary, positional and record constructors,
# infix constructors with random fixities, a type parameter, newtypes,
# fields of other declared types and of the type itself -- deriving Show
# and a random choice of Eq, Ord, Read, Enum and Bounded (where GHC can),
# and probes what deriving produces: show at several precedences and inside
# other values, read of shown text (respaced and reparenthesised), compare,
# ranges and succ/pred at the ends, minBound/maxBound, record selectors and
# updates on the wrong constructor, and :t of constructors.
module Fuzz
  class DataGen
    BASE = [['Int', -> (g) { g.int }], ['Integer', -> (g) { g.int(big: true) }], ['Double', -> (g) { g.dbl }],
            ['Bool', -> (g) { g.pick(%w[True False]) }], ['Char', -> (g) { g.pick(["'a'", "'\\n'", "'\\955'", "'\"'"]) }],
            ['String', -> (g) { g.pick(['"x"', '""', '"a b"', '"\\955\\&1"']) }],
            ['Maybe Int', -> (g) { g.pick(['Nothing', "Just #{g.int}"]) }], ['[Int]', -> (g) { "[#{g.int}, #{g.int}]" }]].freeze
    OPS = %w[:+: :*: :-> :% :<> :=> :& :|].freeze

    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    def int(big: false)
      v = big && chance(0.3) ? @r.rand(-(10**25)..(10**25)) : pick([0, 1, -1, 7, -3, 42, -100])
      v.negative? ? "(#{v})" : v.to_s
    end

    def dbl
      pick(['0.5', '(-2.5)', '1.0e-2', '1.0e7', '(-0.0)', '3.0'])
    end

    # ---- declarations -------------------------------------------------------------

    # A type: {name:, param:, cons: [{name:, fields: [[label or nil, type]], infix: op or nil}],
    # newtype:, derives:}.
    def declare(i, earlier)
      name = "T#{i}"
      param = chance(0.25) ? 'a' : nil
      if chance(0.15)
        field = chance(0.5) ? ["un#{name}", pick(BASE)[0]] : [nil, pick(BASE)[0]]
        cons = [{ name: "N#{i}", fields: [field] }]
        return finish({ name: name, param: nil, cons: cons, newtype: true }, earlier)
      end
      cons = Array.new(@r.rand(1..4)) do |j|
        cname = "C#{i}#{(j + 97).chr}"
        case @r.rand(6)
        when 0, 1 then { name: cname, fields: [] }
        when 2 then { name: cname, fields: Array.new(@r.rand(1..3)) { [nil, field_type(name, param, earlier)] } }
        when 3 then { name: cname, fields: Array.new(@r.rand(1..3)) { |k| ["f#{i}#{(j + 97).chr}#{k}", field_type(name, param, earlier)] } }
        else { name: nil, infix: (@ops ||= OPS.shuffle(random: @r)).pop || ":+#{i}#{j}:",
               fields: [[nil, field_type(name, param, earlier)], [nil, field_type(name, param, earlier)]],
               fixity: [pick(%w[infixl infixr infix]), @r.rand(0..9)] }
        end
      end
      # A recursive field needs a way out.
      cons.unshift({ name: "E#{i}", fields: [] }) if cons.all? { |c| c[:fields].any? { |_, t| t.start_with?(name) } }
      finish({ name: name, param: param, cons: cons, newtype: false }, earlier)
    end

    def field_type(self_name, param, earlier)
      case @r.rand(10)
      when 0 then param || pick(BASE)[0]
      when 1 then earlier.empty? ? pick(BASE)[0] : applied(pick(earlier))
      when 2 then "#{self_name}#{param ? " #{param}" : ''}"
      else pick(BASE)[0]
      end
    end

    def applied(t)
      t[:param] ? "(#{t[:name]} Int)" : t[:name]
    end

    def finish(t, earlier)
      nullary = t[:cons].all? { |c| c[:fields].empty? }
      fields = t[:cons].flat_map { |c| c[:fields].map { |_, ft| ft } }
      # Field types whose instances exist for every class derived here.
      plain = fields.all? { |ft| BASE.any? { |b, _| b == ft } || ft == t[:param] }
      derives = ['Show']
      derives << 'Eq' if chance(0.8)
      derives << 'Ord' if derives.include?('Eq') && chance(0.7)
      derives << 'Read' if chance(0.7)
      derives << 'Enum' if nullary && chance(0.7)
      bounded_ok = nullary || (t[:cons].length == 1 && fields.all? { |ft| %w[Int Bool Char].include?(ft) })
      derives << 'Bounded' if bounded_ok && chance(0.6)
      # Only what every declared type in a field derives too.
      earlier.each do |u|
        next unless fields.any? { |ft| ft == u[:name] || ft == "(#{u[:name]} Int)" }

        derives &= u[:derives]
      end
      t[:derives] = derives
      t[:plain] = plain
      earlier << t
      t
    end

    def decl_text(t)
      lines = []
      head = "#{t[:newtype] ? 'newtype' : 'data'} #{t[:name]}#{t[:param] ? " #{t[:param]}" : ''} ="
      alts = t[:cons].map { |c| con_text(c) }
      lines << "#{head} #{alts.join(' | ')}"
      lines << "  deriving (#{t[:derives].join(', ')})"
      t[:cons].each { |c| lines << "#{c[:fixity][0]} #{c[:fixity][1]} #{c[:infix]}" if c[:infix] }
      ":{\n#{lines.join("\n")}\n:}"
    end

    def paren_type(ft)
      ft.include?(' ') && !ft.start_with?('(', '[') ? "(#{ft})" : ft
    end

    def con_text(c)
      return "#{paren_type(c[:fields][0][1])} #{c[:infix]} #{paren_type(c[:fields][1][1])}" if c[:infix]
      return c[:name] if c[:fields].empty?
      return "#{c[:name]} { #{c[:fields].map { |l, ft| "#{l} :: #{ft}" }.join(', ')} }" if c[:fields][0][0]

      "#{c[:name]} #{c[:fields].map { |_, ft| paren_type(ft) }.join(' ')}"
    end

    # ---- values -----------------------------------------------------------------

    def value(t, depth = 2)
      cons = depth <= 0 ? t[:cons].select { |c| c[:fields].none? { |_, ft| ft.start_with?(t[:name]) } } : t[:cons]
      cons = t[:cons] if cons.empty?
      c = pick(cons)
      args = c[:fields].map { |_, ft| field_value(t, ft, depth - 1) }
      return "(#{args[0]} #{c[:infix]} #{args[1]})" if c[:infix]
      return c[:name] if args.empty?
      return "(#{c[:name]} { #{c[:fields].each_with_index.map { |(l, _), k| "#{l} = #{args[k]}" }.join(', ')} })" if c[:fields][0][0]

      "(#{c[:name]} #{args.join(' ')})"
    end

    def field_value(t, ft, depth)
      return int if ft == t[:param] || ft == 'a'
      return value(t, depth) if ft.start_with?(t[:name])

      other = @types.find { |u| ft == u[:name] || ft == "(#{u[:name]} Int)" }
      return value(other, depth) if other

      BASE.find { |b, _| b == ft }[1].call(self)
    end

    def typed(t, v)
      "(#{v} :: #{t[:param] ? "#{t[:name]} Int" : t[:name]})"
    end

    def type_name(t)
      t[:param] ? "(#{t[:name]} Int)" : t[:name]
    end

    # ---- probes -----------------------------------------------------------------

    def section(n)
      @ops = nil
      @types = []
      out = ['import Data.List']
      @r.rand(1..3).times { |i| out << decl_text(declare(i + 1, @types)) }
      n.times { out << probe }
      out
    end

    def probe
      t = pick(@types)
      raw = value(t)
      v = typed(t, raw)
      d = t[:derives]
      choices = [-> { v }, -> { "showsPrec #{pick([0, 6, 7, 10, 11])} #{v} \"\"" }, -> { "Just #{v}" },
                 -> { "[#{v}, #{typed(t, value(t))}]" }, -> { "(#{v}, #{int})" }, -> { ":t #{con_ref(t)}" }]
      if d.include?('Read')
        choices << -> { "read (show #{v}) :: #{type_name(t)}" }
        choices << -> { "read #{respace(raw).inspect} :: #{type_name(t)}" }
        choices << -> { "(reads :: ReadS #{type_name(t)}) #{(respace(raw) + pick(['', ' rest', ')'])).inspect}" }
        choices << -> { "read (show (Just #{v})) :: Maybe #{type_name(t)}" }
      end
      if d.include?('Eq')
        choices << -> { "#{v} == #{typed(t, value(t))}" }
        choices << -> { "(read (show #{v}) :: #{type_name(t)}) == #{v}" } if d.include?('Read')
      end
      if d.include?('Ord')
        choices << -> { "compare #{v} #{typed(t, value(t))}" }
        choices << -> { "sort [#{v}, #{typed(t, value(t))}, #{typed(t, value(t))}]" }
        choices << -> { "maximum [#{v}, #{typed(t, value(t))}]" }
      end
      if d.include?('Enum')
        choices << -> { "[minBound .. maxBound] :: [#{t[:name]}]" } if d.include?('Bounded')
        choices << -> { "succ #{v}" } << -> { "pred #{v}" } << -> { "fromEnum #{v}" }
        choices << -> { "toEnum (#{@r.rand(-1..t[:cons].length)}) :: #{t[:name]}" }
        choices << -> { "[#{v} ..]" } << -> { "[#{v}, #{typed(t, value(t))} ..]" }
        choices << -> { "[#{v} .. #{typed(t, value(t))}]" }
      end
      choices << -> { "(minBound :: #{type_name(t)}, maxBound :: #{type_name(t)})" } if d.include?('Bounded')
      labels = t[:cons].flat_map { |c| c[:fields].map { |l, ft| [l, ft] } }.select { |l, _| l }
      unless labels.empty?
        l, ft = pick(labels)
        choices << -> { "#{l} #{v}" }
        choices << -> { "#{v} { #{l} = #{field_value(t, ft, 0)} }" }
      end
      pick(choices).call
    end

    def con_ref(t)
      c = pick(t[:cons])
      c[:infix] ? "(#{c[:infix]})" : c[:name]
    end

    # The same text with other spacing and redundant parentheses (both
    # read accepts).
    def respace(v)
      s = v.gsub(' ', pick([' ', '  ', "\t"]))
      s = "(#{s})" if chance(0.3)
      s = " #{s} " if chance(0.3)
      s
    end
  end
end
