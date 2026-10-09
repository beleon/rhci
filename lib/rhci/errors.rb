# frozen_string_literal: true

module Rhci
  # A failure attributable to the Haskell input rather than to rhci.
  # `kind` maps onto Result statuses: :parse, :scope, :compile, :unsupported.
  class Error < StandardError
    # detail: the message without its source location prefix.
    attr_reader :kind, :line, :col, :detail

    def initialize(kind, message, line = nil, col = nil, source = '<interactive>')
      @kind = kind
      @line = line
      @col = col
      @detail = message
      super(line ? "#{source}:#{line}:#{col}: #{message}" : message)
    end
  end

  # Lexical errors, syntax errors and operator-precedence errors.
  class ParseError < Error
    def initialize(message, line = nil, col = nil, source = '<interactive>')
      super(:parse, message, line, col, source)
    end
  end

  # Valid Haskell (or plausibly so) that rhci deliberately does not accept
  # rather than approximate.
  class UnsupportedError < Error
    def initialize(message, line = nil, col = nil, source = '<interactive>')
      super(:unsupported, message, line, col, source)
    end
  end
end
