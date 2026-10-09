# frozen_string_literal: true

module Rhci
  # Command-line front end shared by bin/rhci (CRuby) and the mruby binary.
  module CLI
    EXIT_OK          = 0
    EXIT_EXCEPTION   = 1 # uncaught Haskell exception at run time
    EXIT_USAGE       = 2
    EXIT_COMPILE     = 3 # parse, scope or type error
    EXIT_UNSUPPORTED = 4 # outside what rhci implements exactly

    PROMPT = 'rhci> '
    CONTINUATION_PROMPT = 'rhci| '

    USAGE = <<~TEXT
      usage: rhci [FILE.hs...]                 interactive session
             rhci [-i] -c EXPR [ARG...]        apply pure EXPR to ARGs (Haskell expressions)
             rhci [-i] -x EXPR [ARG...]        run IO action EXPR; ARGs via getArgs
             rhci -h | --help | --version

        -i   apply the result to standard input as a lazy String (like interact)

      Strings print raw; other values print with show. Exit status: 0 ok,
      1 Haskell exception, 2 usage error, 3 parse/scope/type error, 4 unsupported.
    TEXT

    class UsageError < StandardError; end

    class Options
      attr_reader :action, :mode, :expr, :args, :files, :interact

      def initialize(action, mode, expr, args, files, interact)
        @action = action     # :repl, :run, :help, :version
        @mode = mode         # :pure, :io (for :run)
        @expr = expr
        @args = args
        @files = files
        @interact = interact
      end
    end

    def self.parse(argv)
      files = []
      interact = false
      i = 0
      while i < argv.length
        arg = argv[i]
        case arg
        when '-h', '--help'
          return Options.new(:help, nil, nil, [], [], false)
        when '--version'
          return Options.new(:version, nil, nil, [], [], false)
        when '-i'
          interact = true
        when '-c', '-x'
          expr = argv[i + 1]
          raise UsageError, "#{arg} requires an expression" if expr.nil?

          mode = arg == '-c' ? :pure : :io
          # Everything after EXPR is an argument, even if it looks like a flag.
          return Options.new(:run, mode, expr, argv[(i + 2)..-1], files, interact)
        else
          raise UsageError, "unknown option #{arg}" if arg.length > 1 && arg[0] == '-'

          files << arg
        end
        i += 1
      end
      raise UsageError, '-i requires -c or -x' if interact

      Options.new(:repl, nil, nil, [], files, false)
    end

    def self.main(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
      begin
        opts = parse(argv)
      rescue UsageError => e
        Shim.write(stderr, "rhci: #{e.message}\n#{USAGE}")
        return EXIT_USAGE
      end

      case opts.action
      when :help
        Shim.write(stdout, USAGE)
        EXIT_OK
      when :version
        Shim.write(stdout, "rhci #{VERSION}\n")
        EXIT_OK
      when :run
        run(opts, stdin, stdout, stderr)
      else
        repl(opts, stdin, stdout, stderr)
      end
    end

    def self.run(opts, stdin, stdout, stderr)
      session = Session.new(stdout: stdout, stdin: stdin, stderr: stderr)
      result =
        if opts.mode == :pure
          session.run_pure(opts.expr, opts.args, interact: opts.interact)
        else
          session.run_io(opts.expr, opts.args, interact: opts.interact)
        end
      report(result, stderr)
      Shim.flush(stdout)
      exit_code(result)
    end

    def self.repl(opts, stdin, stdout, stderr)
      session = Session.new(stdout: stdout, stdin: stdin, stderr: stderr)
      editor = line_editor(session, stdin, stdout)
      report(session.load(opts.files), stderr) unless opts.files.empty?
      loop do
        input = read_input(session, stdout, editor)
        if input.nil?
          Shim.write(stdout, "\n")
          return EXIT_OK
        end
        next if input == :interrupt || Rhci::Text.blank?(input)
        return EXIT_OK if quit?(input)

        report(session.eval(input), stderr)
        Shim.flush(stdout)
      end
    end

    # One input: a line, or the lines between `:{` and `:}` joined with
    # newlines (layout intact). nil at end of input; :interrupt when Ctrl-C
    # abandoned it.
    def self.read_input(session, stdout, editor = nil)
      line = prompt_line(session, stdout, PROMPT, editor)
      return line if line.nil? || line == :interrupt
      return line unless Rhci::Text.strip(line) == ':{'

      lines = []
      loop do
        l = prompt_line(session, stdout, CONTINUATION_PROMPT, editor)
        return l if l.nil? || l == :interrupt
        return lines.join("\n") if Rhci::Text.strip(l) == ':}'

        lines << l
      end
    end

    def self.prompt_line(session, stdout, prompt, editor)
      return edit_line(session, prompt, editor) if editor

      Shim.write(stdout, prompt)
      Shim.flush(stdout)
      line = session.read_line
      if line == :interrupt
        Shim.write(stdout, "\n")
        return line
      end
      line&.chomp
    end

    # ---- the interactive terminal ----------------------------------------------

    # A line editor when stdin and stdout are a terminal, else nil (input is
    # then read line by line, as from a pipe). Also routes Ctrl-C during
    # evaluation to the session.
    def self.line_editor(session, stdin, stdout)
      return nil unless Shim.tty?(stdin) && Shim.tty?(stdout)

      Shim.trap_interrupt { session.interrupt! }
      @history_path = history_path
      completer = ->(text) { session.completions(text) }
      LineEditor.new(LineEditor::Tty.new(stdin, stdout), history: load_history, completer: completer)
    end

    def self.edit_line(session, prompt, editor)
      editor.term.raw
      line = begin
        editor.read_line(prompt, session.pending_input)
      ensure
        editor.term.cooked
      end
      save_history(line) if line.is_a?(String)
      line
    end

    def self.history_path
      home = Shim.getenv('HOME')
      home.nil? || home.empty? ? nil : "#{home}/.rhci_history"
    end

    def self.load_history
      text = @history_path ? Shim.read_file(@history_path) : nil
      return [] if text.nil?

      lines = text.split("\n")
      lines.length > LineEditor::HISTORY_MAX ? lines[-LineEditor::HISTORY_MAX..-1] : lines
    end

    def self.save_history(line)
      return if @history_path.nil? || Rhci::Text.blank?(line)

      Shim.append_file(@history_path, "#{line}\n")
    rescue StandardError
      @history_path = nil # an unwritable history file is not worth an error
    end

    def self.quit?(input)
      s = Rhci::Text.strip(input)
      return false unless s.start_with?(':') && !s.include?(' ')

      Session.command_name(s[1..-1]) == 'quit'
    end

    def self.report(result, stderr)
      return if result.ok?

      text = case result.status
             when :exception then "*** Exception: #{result.message}"
             when :unsupported then "unsupported: #{result.message}"
             else result.message
             end
      Shim.write(stderr, "#{text}\n")
      Shim.flush(stderr)
    end

    def self.exit_code(result)
      case result.status
      when :ok then EXIT_OK
      when :exception, :limit then EXIT_EXCEPTION
      when :unsupported then EXIT_UNSUPPORTED
      when :command_error then EXIT_USAGE
      else EXIT_COMPILE
      end
    end
  end
end
