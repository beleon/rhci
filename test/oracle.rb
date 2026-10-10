# frozen_string_literal: true

# Reads oracle/golden-*.txt (real GHCi output) and classifies each probe,
# so tests can compare rhci against GHCi by meaning (oracle/README.md).
module Oracle
  class Probe
    attr_reader :section, :input, :output

    def initialize(section, input)
      @section = section
      @input = input
      @output = []
    end

    def add_input_line(line)
      @input = "#{@input}\n#{line}"
    end

    # GHCi's output without its warnings (rhci emits none, by decision).
    def text
      lines = []
      skipping = false
      @output.each do |l|
        if l.include?(': warning:')
          skipping = true
        elsif skipping && (l.start_with?('    ') || Rhci::Text.blank?(l))
          next
        else
          skipping = false
          lines << l
        end
      end
      Rhci::Text.strip(lines.join("\n"))
    end

    # :parse (a lexical/parse/fixity error), :command (unknown command),
    # or :parsed (anything else: success, scope/type/runtime errors).
    def ghci_class
      t = text
      return :parse if t.include?('parse error') || t.include?('lexical error') ||
                       t.include?('Precedence parsing error')
      return :command if t.start_with?('unknown command')

      :parsed
    end

    # The source rhci's front end should see: the body of a :{ :} block, the
    # argument of :type, the input itself, or nil for other commands.
    def frontend_input
      if @input.start_with?(":{\n")
        lines = @input.split("\n")
        return lines[1..-2].join("\n")
      end
      return @input unless @input.start_with?(':')

      word, arg = @input[1..-1].split(' ', 2)
      return nil unless Rhci::Session.command_name(word.to_s) == 'type'
      return nil if arg.nil? || Rhci::Text.blank?(arg)

      [:type, arg]
    end
  end

  # ---- semantic comparison ------------------------------------------------

  # GHCi output -> :ok, :parse, :scope, :compile, :runtime, :command.
  def self.outcome(text)
    t = Rhci::Text.strip(text)
    return :parse if t.include?('parse error') || t.include?('lexical error') || t.include?('Precedence parsing error')
    return :command if t.start_with?('unknown command') || t.include?('not an expression')
    return :scope if t.include?('not in scope') || t.include?('Not in scope')
    return :runtime if t.include?('*** Exception')
    return :compile if t.include?('error:') || t.include?('Module graph contains a cycle')

    :ok
  end

  # A type string -> [body tokens, sorted constraint strings], with type
  # variables renamed in order of first appearance and String (and FilePath) spelled [Char].
  def self.normalize_type(s)
    s = s.sub('GHC.Stack.Types.HasCallStack => ', '')
    ctx = nil
    k = s.index(' => ')
    if k
      ctx = s[0, k]
      s = s[(k + 4)..-1]
    end
    names = {}
    body = canonical(rename_tokens(type_tokens(s), names))
    constraints = []
    if ctx
      c = Rhci::Text.strip(ctx)
      c = c[1..-2] if c.start_with?('(') && c.end_with?(')')
      c.split(', ').each { |one| constraints << rename_tokens(type_tokens(one), names).join(' ') }
    end
    [body, constraints.sort]
  end

  def self.type_tokens(s)
    toks = []
    i = 0
    while i < s.length
      c = s[i]
      if c == ' '
        i += 1
      elsif '()[],'.include?(c)
        toks << c
        i += 1
      elsif c == '-' && s[i + 1] == '>'
        toks << '->'
        i += 2
      else
        j = i
        j += 1 while j < s.length && !' ()[],'.include?(s[j]) && !(s[j] == '-' && s[j + 1] == '>')
        toks << s[i...j]
        i = j
      end
    end
    out = []
    toks.each do |t|
      # A type constructor's module qualifier (M.Map) is how it is in
      # scope, not what it is.
      dot = t.rindex('.')
      t = t[(dot + 1)..-1] if dot && dot.positive? && t[0] >= 'A' && t[0] <= 'Z' && dot < t.length - 1
      if t == 'String' || t == 'FilePath'
        out.concat(['[', 'Char', ']'])
      else
        out << t
      end
    end
    out
  end

  # Type synonyms GHC keeps in :t output and rhci expands.
  SYNONYMS = { 'ReadS' => 1, 'ShowS' => 0 }.freeze

  # Tokens re-printed from a parse, with the synonyms above expanded, so
  # redundant parentheses and synonym use do not matter.
  def self.canonical(toks)
    pos = [0]
    t = parse_fun(toks, pos)
    return toks unless pos[0] == toks.length

    show_type(t, false).split(' ')
  end

  def self.parse_fun(toks, pos)
    a = parse_app(toks, pos)
    return a unless toks[pos[0]] == '->'

    pos[0] += 1
    [:fun, a, parse_fun(toks, pos)]
  end

  def self.parse_app(toks, pos)
    parts = []
    while pos[0] < toks.length && !['->', ')', ']', ','].include?(toks[pos[0]])
      parts << parse_atom(toks, pos)
    end
    head = parts[0]
    if head.is_a?(String) && SYNONYMS.key?(head) && parts.length == SYNONYMS[head] + 1
      return expand(head, parts[1..])
    end

    parts.length == 1 ? parts[0] : [:app, parts]
  end

  def self.expand(name, args)
    str = [:list, 'Char']
    if name == 'ShowS' then [:fun, str, str]
    else [:fun, str, [:list, [:tuple, [args[0], str]]]]
    end
  end

  def self.parse_atom(toks, pos)
    t = toks[pos[0]]
    pos[0] += 1
    if t == '['
      inner = parse_fun(toks, pos)
      pos[0] += 1
      [:list, inner]
    elsif t == '('
      items = []
      until toks[pos[0]] == ')' || pos[0] >= toks.length
        items << parse_fun(toks, pos)
        pos[0] += 1 if toks[pos[0]] == ','
      end
      pos[0] += 1
      items.length == 1 ? items[0] : [:tuple, items]
    else
      t
    end
  end

  def self.show_type(t, wrap)
    return t if t.is_a?(String)

    case t[0]
    when :fun
      s = "#{show_type(t[1], true)} -> #{show_type(t[2], false)}"
      wrap ? "( #{s} )" : s
    when :app
      s = t[1].map { |x| x.is_a?(Array) && %i[fun app].include?(x[0]) ? "( #{show_type(x, false)} )" : show_type(x, true) }.join(' ')
      wrap ? "( #{s} )" : s
    when :list then "[ #{show_type(t[1], false)} ]"
    else "( #{t[1].map { |x| show_type(x, false) }.join(' , ')} )"
    end
  end

  def self.rename_tokens(toks, names)
    toks.map do |t|
      c = t[0]
      if c >= 'a' && c <= 'z'
        names[t] ||= "v#{names.length}"
      else
        t
      end
    end
  end

  def self.load(path)
    probes = []
    section = nil
    current = nil
    File.read(path).split("\n").each do |line|
      if line.start_with?('## ')
        section = line[3..-1]
        current = nil
      elsif line.start_with?('ghci> ')
        current = Probe.new(section, line[6..-1])
        probes << current
      elsif line.start_with?('ghci| ')
        current.add_input_line(line[6..-1])
      elsif current && !line.start_with?('-- ')
        current.output << line
      end
    end
    probes
  end

  # oracle/known_gaps.txt: "stage | input | reason" lines; '#' comments.
  def self.known_gaps(path, stage)
    gaps = {}
    File.read(path).split("\n").each do |line|
      next if Rhci::Text.blank?(line) || line.start_with?('#')

      st, input, = line.split(' | ', 3)
      gaps[input] = true if st == stage
    end
    gaps
  end
end
