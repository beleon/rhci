# frozen_string_literal: true

# A compact S-expression syntax for hand-written Core in tests:
#   x  42  -3  4.5  "str"         variable, Integer, Float, string literal
#   (\ (x y) body)                 lambda
#   (let ((x e) (y e)) body)       recursive let
#   (case e b ((Con x y) body) ((lit 3) body) (_ body))   b may be _
#   (con Name a b)  (prim op a b)  (f a b)
#   (def name expr)                a global (CoreProgram only)
module CoreSexp
  include Rhci

  CONS = {
    'Unit' => VM::Builtins::UNIT, 'True' => VM::Builtins::TRUE, 'False' => VM::Builtins::FALSE,
    'Nil' => VM::Builtins::NIL, 'Cons' => VM::Builtins::CONS, 'IORes' => VM::Builtins::IORES,
    'Tup2' => VM::Builtins.tuple(2), 'LT' => VM::Builtins::LT, 'EQ' => VM::Builtins::EQ, 'GT' => VM::Builtins::GT
  }
  NOTHING, JUST = Core.data_type('Maybe', [['Nothing', 0], ['Just', 1]])
  CONS['Nothing'] = NOTHING
  CONS['Just'] = JUST

  def self.read_all(src)
    toks = tokenize(src)
    out = []
    pos = [0]
    out << read(toks, pos) while pos[0] < toks.length
    out
  end

  def self.tokenize(src)
    toks = []
    i = 0
    while i < src.length
      c = src[i]
      if c == '(' || c == ')'
        toks << c
        i += 1
      elsif c == ' ' || c == "\n" || c == "\t"
        i += 1
      elsif c == ';'
        i += 1 while i < src.length && src[i] != "\n"
      elsif c == '"'
        j = i + 1
        j += 1 while src[j] != '"'
        toks << [:str, src[(i + 1)...j]]
        i = j + 1
      else
        j = i
        j += 1 while j < src.length && !" ()\n\t".include?(src[j])
        toks << src[i...j]
        i = j
      end
    end
    toks
  end

  def self.read(toks, pos)
    t = toks[pos[0]]
    pos[0] += 1
    return t unless t == '('

    list = []
    while toks[pos[0]] != ')'
      raise 'core sexp: unbalanced' if pos[0] >= toks.length

      list << read(toks, pos)
    end
    pos[0] += 1
    list
  end

  def self.number?(s)
    c = s[0]
    (c >= '0' && c <= '9') || (c == '-' && s.length > 1 && s[1] >= '0' && s[1] <= '9')
  end

  def self.core(x)
    if x.is_a?(Array) && x[0] == :str
      Core::Str.new(x[1].codepoints)
    elsif x.is_a?(String)
      return Core::Lit.new(x.include?('.') ? x.to_f : x.to_i) if number?(x)

      Core::Var.new(x)
    else
      case x[0]
      when '\\' then Core::Lam.new(x[1], core(x[2]))
      when 'let' then Core::Let.new(x[1].map { |n, e| [n, core(e)] }, core(x[2]))
      when 'case'
        alts = x[3..-1].map do |pat, body|
          if pat == '_' then Core::Alt.new(:default, nil, [], core(body))
          elsif pat[0] == 'lit' then Core::Alt.new(:lit, core(pat[1]).value, [], core(body))
          else Core::Alt.new(:con, CONS.fetch(pat[0]), pat[1..-1], core(body))
          end
        end
        Core::Case.new(core(x[1]), x[2] == '_' ? nil : x[2], alts)
      when 'con' then Core::Con.new(CONS.fetch(x[1]), x[2..-1].map { |a| core(a) })
      when 'prim' then Core::Prim.new(x[1].to_sym, x[2..-1].map { |a| core(a) })
      else Core::App.new(core(x[0]), x[1..-1].map { |a| core(a) })
      end
    end
  end

  # Globals from (def ...) forms, compiled into fresh cells.
  class Program
    attr_reader :machine, :globals

    def initialize(src, out = nil, limits = nil)
      @globals = {}
      @machine = Rhci::VM::Machine.new(out, limits)
      defs = CoreSexp.read_all(src)
      defs.each { |d| @globals[d[1]] = Rhci::VM::Cell.new(d[1]) }
      lower = Rhci::Lower.new(@globals)
      defs.each { |d| @globals[d[1]].value = lower.global_value(d[1], CoreSexp.core(d[2])) }
    end

    # Evaluate an expression (S-expression text) to WHNF.
    def eval(src)
      code = Rhci::Lower.new(@globals).expression(CoreSexp.core(CoreSexp.read_all(src)[0]))
      @machine.eval_code(code)
    end
  end
end
