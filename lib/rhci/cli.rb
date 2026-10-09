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
      session = Session.new(stdout: stdout, stdin: stdin)
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
      session = Session.new(stdout: stdout, stdin: stdin)
      report(session.load(opts.files), stderr) unless opts.files.empty?
      loop do
        Shim.write(stdout, PROMPT)
        Shim.flush(stdout)
        line = Shim.read_line(stdin)
        if line.nil?
          Shim.write(stdout, "\n")
          return EXIT_OK
        end
        input = line.strip
        next if input.empty?
        return EXIT_OK if input == ':q' || input == ':quit'

        report(session.eval(input), stderr)
        Shim.flush(stdout)
      end
    end

    def self.report(result, stderr)
      return if result.ok?

      prefix = result.status == :exception ? '*** Exception' : result.status.to_s.tr('_', ' ')
      Shim.write(stderr, "#{prefix}: #{result.message}\n")
      Shim.flush(stderr)
    end

    def self.exit_code(result)
      case result.status
      when :ok then EXIT_OK
      when :exception, :limit then EXIT_EXCEPTION
      when :unsupported then EXIT_UNSUPPORTED
      else EXIT_COMPILE
      end
    end
  end
end
