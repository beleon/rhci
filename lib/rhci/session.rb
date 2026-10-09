# frozen_string_literal: true

module Rhci
  # Outcome of one input. `status` is one of:
  #   :ok, :parse_error, :scope_error, :type_error, :exception,
  #   :unsupported, :limit
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

    # Evaluate one GHCi input (expression, declarations, `let`, command).
    def eval(input)
      not_implemented
    end

    # `rhci -c EXPR ARG...`: apply a pure EXPR to ARGs, each a Haskell
    # expression.
    def run_pure(expr, args, interact: false)
      not_implemented
    end

    # `rhci -x EXPR ARG...`: run an IO EXPR; ARGs are visible via getArgs.
    def run_io(expr, args, interact: false)
      not_implemented
    end

    private

    def not_implemented
      Result.new(:unsupported, 'evaluation is not implemented yet')
    end
  end
end
