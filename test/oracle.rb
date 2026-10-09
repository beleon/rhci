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
    return :compile if t.include?('error:') || t.include?('error: [')

    :ok
  end

  # A type string -> [body tokens, sorted constraint strings], with type
  # variables renamed in order of first appearance and String spelled [Char].
  def self.normalize_type(s)
    s = s.sub('GHC.Stack.Types.HasCallStack => ', '')
    ctx = nil
    k = s.index(' => ')
    if k
      ctx = s[0, k]
      s = s[(k + 4)..-1]
    end
    names = {}
    body = rename_tokens(type_tokens(s), names)
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
      if t == 'String'
        out.concat(['[', 'Char', ']'])
      else
        out << t
      end
    end
    out
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
