# frozen_string_literal: true

module Rhci
  # Outcome of one input. `status` is one of:
  #   :ok, :parse_error, :scope_error, :compile_error, :exception,
  #   :unsupported, :limit, :command_error
  class Result
    attr_reader :status, :message

    def initialize(status, message = nil)
      @status = status
      @message = message
    end

    def ok?
      @status == :ok
    end
  end

  # One independent interpreter state: the embedding API. Output produced by
  # Haskell code goes to `stdout`; nothing is written anywhere else.
  class Session
    def initialize(stdout: nil, stdin: nil, limits: nil)
      @stdout = stdout
      @stdin = stdin
      @limits = limits
    end

    # GHCi commands, in the order GHCi resolves abbreviations (`:t` is
    # `:type`). :quit is the CLI's business.
    COMMANDS = %w[? help load quit reload type].freeze

    # Evaluate one GHCi input (expression, declarations, `let`, command).
    def eval(input)
      return command(input) if input.lstrip.start_with?(':')

      Frontend.parse_repl(input)
      not_implemented
    rescue Error => e
      failure(e)
    end

    # The full command name an abbreviation stands for, or nil.
    def self.command_name(word)
      return nil if word.empty?

      COMMANDS.find { |c| c.start_with?(word) }
    end

    # `:load PATH...` / `rhci PATH...`: replace the loaded modules.
    def load(paths)
      not_implemented
    end

    # `rhci -c EXPR ARG...`: apply a pure EXPR to ARGs, each a Haskell
    # expression.
    def run_pure(expr, args, interact: false)
      Frontend.parse_expression(expr)
      args.each { |a| Frontend.parse_expression(a) }
      not_implemented
    rescue Error => e
      failure(e)
    end

    # `rhci -x EXPR ARG...`: run an IO EXPR; ARGs are visible via getArgs.
    def run_io(expr, args, interact: false)
      Frontend.parse_expression(expr)
      not_implemented
    rescue Error => e
      failure(e)
    end

    private

    def command(input)
      text = input.lstrip[1..-1]
      word, arg = split_word(text)
      case Session.command_name(word)
      when 'type'
        return Result.new(:command_error, 'not an expression: ‘’') if arg.strip.empty?

        # Positions are relative to the argument, as in GHCi.
        Frontend.parse_expression(arg.lstrip)
        Result.new(:unsupported, 'type inference is not implemented yet')
      when nil
        Result.new(:command_error, "unknown command ':#{word}'\nuse :? for help.")
      else
        Result.new(:unsupported, ":#{Session.command_name(word)} is not implemented yet")
      end
    rescue Error => e
      failure(e)
    end

    def split_word(text)
      i = 0
      i += 1 while i < text.length && text[i] != ' ' && text[i] != "\t" && text[i] != "\n"
      [text[0, i], text[i..-1] || '']
    end

    def failure(err)
      status = { parse: :parse_error, scope: :scope_error, compile: :compile_error,
                 unsupported: :unsupported }[err.kind] || :compile_error
      Result.new(status, err.message)
    end

    def not_implemented
      Result.new(:unsupported, 'evaluation is not implemented yet')
    end
  end
end
