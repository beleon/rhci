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

    def text
      @output.join("\n").strip
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
      return nil if arg.nil? || arg.strip.empty?

      [:type, arg]
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
      next if line.strip.empty? || line.start_with?('#')

      st, input, = line.split(' | ', 3)
      gaps[input] = true if st == stage
    end
    gaps
  end
end
