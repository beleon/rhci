# frozen_string_literal: true

module Rhci
  # Token stream implementing the Haskell layout algorithm (Report 10.3).
  #
  # The context stack holds the indentation of each enclosing implicit
  # block (> 0) or 0 for an explicit `{`. Virtual `;` (:vsemi) and `}`
  # (:vrbrace) tokens are synthesised on demand when the parser peeks at
  # the first token of a line. The parse-error(t) rule -- an implicit block
  # closes when its contents cannot continue, as in `let x = 1 in x` -- is
  # the parser's job, through #close_implicit.
  class Cursor
    def initialize(tokens, source)
      @toks = tokens
      @source = source
      @pos = 0
      @ctx = []
      @virt = nil
      @checked = -1 # index of the token already checked against the layout
    end

    def peek
      return @virt if @virt

      t = @toks[@pos]
      m = @ctx.last
      if t.kind == :eof
        @virt = virtual(:vrbrace, '}', t) if m && m > 0
      elsif t.bol && @checked != @pos && m && m > 0
        if t.col < m
          @virt = virtual(:vrbrace, '}', t)
        elsif t.col == m
          @virt = virtual(:vsemi, ';', t)
        else
          @checked = @pos
        end
      end
      @virt || t
    end

    # The next real token, ignoring any pending virtual one.
    def raw(offset = 0)
      @toks[@pos + offset] || @toks.last
    end

    def advance
      t = peek
      if @virt
        if @virt.kind == :vrbrace
          @ctx.pop
        else
          @checked = @pos
        end
        @virt = nil
      else
        if t.is?(:special, '{')
          @ctx.push(0)
        elsif t.is?(:special, '}')
          raise ParseError.new("parse error on input ‘}’", t.line, t.col, @source) unless @ctx.last == 0

          @ctx.pop
        end
        @pos += 1 unless t.kind == :eof
      end
      t
    end

    # Called right after a layout keyword (let, where, do, of) or at the
    # start of a module/REPL input. Returns :explicit (a `{` was consumed),
    # :implicit (a context was pushed), or :empty (the block is `{}`).
    def open_block
      @virt = nil
      t = @toks[@pos]
      if t.is?(:special, '{')
        advance
        return :explicit
      end
      n = t.kind == :eof ? 0 : t.col
      m = @ctx.last || 0
      return :empty unless n > m

      @ctx.push(n)
      @checked = @pos # the block's first token gets no virtual `;`
      :implicit
    end

    def implicit?
      m = @ctx.last
      !m.nil? && m > 0
    end

    # The parse-error(t) rule: close the innermost implicit block.
    def close_implicit
      @virt = nil
      @ctx.pop
    end

    private

    def virtual(kind, text, at)
      Token.new(kind, text, at.line, at.col, false)
    end
  end
end
