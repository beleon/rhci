# frozen_string_literal: true

module Rhci
  # One lexeme. `name` is the unqualified part of a (possibly qualified)
  # name, `qual` the module prefix or nil. `bol` marks the first token on
  # its source line, which is what the layout algorithm keys on.
  class Token
    attr_reader :kind, :text, :name, :qual, :value, :line, :col, :bol

    def initialize(kind, text, line, col, bol, value = nil, name = nil, qual = nil)
      @kind = kind
      @text = text
      @line = line
      @col = col
      @bol = bol
      @value = value
      @name = name || text
      @qual = qual
    end

    def is?(kind, text = nil)
      @kind == kind && (text.nil? || @text == text)
    end

    def inspect
      "#{@kind}(#{@text})@#{@line}:#{@col}"
    end
  end

  # Haskell 2010 lexical syntax (Report ch. 2) on code points, plus the
  # GHC2021 bits that change how ordinary programs lex: binary literals,
  # numeric underscores, and whitespace-sensitive `!`/`@`.
  #
  # Token kinds:
  #   :varid :conid :qvarid :qconid :varsym :consym :qvarsym :qconsym
  #   :integer (value Integer)  :float (value [mantissa, exp10], exact)
  #   :char (value code point)  :string (value Array of code points)
  #   :special ( ) , ; [ ] ` { }      :keyword      :reservedop
  #   :bang  a prefix-occurrence `!` (bang pattern / strictness mark)
  #   :eof
  # `@` is a :reservedop whose value is :tight, :prefix, :suffix or :loose.
  class Lexer
    KEYWORDS = {}
    %w[case class data default deriving do else foreign if import in infix
       infixl infixr instance let module newtype of then type where _].each { |k| KEYWORDS[k] = true }

    RESERVED_OPS = {}
    ['..', '::', '=', '\\', '|', '<-', '->', '@', '~', '=>'].each { |k| RESERVED_OPS[k] = true }

    SYMBOLS = {}
    '!#$%&*+./<=>?@\\^|-~:'.each_char { |c| SYMBOLS[c.ord] = true }

    SPECIALS = {}
    '(),;[]`{}'.each_char { |c| SPECIALS[c.ord] = true }

    # Opening tokens after which an operator counts as a prefix occurrence.
    OPENERS = {}
    '([,;{'.each_char { |c| OPENERS[c.ord] = true }
    CLOSERS = {}
    ')]},;'.each_char { |c| CLOSERS[c.ord] = true }

    ASCII_ESCAPES = [
      ['NUL', 0], ['SOH', 1], ['STX', 2], ['ETX', 3], ['EOT', 4], ['ENQ', 5],
      ['ACK', 6], ['BEL', 7], ['BS', 8], ['HT', 9], ['LF', 10], ['VT', 11],
      ['FF', 12], ['CR', 13], ['SO', 14], ['SI', 15], ['DLE', 16], ['DC1', 17],
      ['DC2', 18], ['DC3', 19], ['DC4', 20], ['NAK', 21], ['SYN', 22],
      ['ETB', 23], ['CAN', 24], ['EM', 25], ['SUB', 26], ['ESC', 27],
      ['FS', 28], ['GS', 29], ['RS', 30], ['US', 31], ['SP', 32], ['DEL', 127]
    ].freeze
    # Longest match first, so "\SOH" is SOH and not SO followed by 'H'.
    ASCII_ESCAPES_BY_LENGTH = ASCII_ESCAPES.select { |n, _| n.length == 3 } +
                              ASCII_ESCAPES.select { |n, _| n.length == 2 }

    SIMPLE_ESCAPES = { 'a' => 7, 'b' => 8, 'f' => 12, 'n' => 10, 'r' => 13,
                       't' => 9, 'v' => 11, '\\' => 92, '"' => 34, "'" => 39 }.freeze

    MAX_CHAR = 0x10FFFF

    def self.tokenize(src, source = '<interactive>')
      new(src, source).tokenize
    end

    def initialize(src, source)
      @cs = src.codepoints
      @source = source
      @i = 0
      @line = 1
      @col = 1
      @last_line = 0
      @tokens = []
    end

    def tokenize
      loop do
        skip_whitespace_and_comments
        if @i >= @cs.length
          @tokens << Token.new(:eof, '', @line, @col, true)
          return @tokens
        end
        lex_token
      end
    end

    private

    def error(msg, line = @line, col = @col)
      raise ParseError.new(msg, line, col, @source)
    end

    def cur(k = 0)
      @cs[@i + k]
    end

    def digit?(c, base = 10)
      return false if c.nil?

      case base
      when 10 then c >= 48 && c <= 57
      when 16 then (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
      when 8 then c >= 48 && c <= 55
      else c == 48 || c == 49
      end
    end

    def digit_value(c)
      return c - 48 if c <= 57
      return c - 87 if c >= 97

      c - 55
    end

    def lower?(c)
      !c.nil? && ((c >= 97 && c <= 122) || c == 95)
    end

    def upper?(c)
      !c.nil? && c >= 65 && c <= 90
    end

    def ident_char?(c)
      lower?(c) || upper?(c) || digit?(c) || c == 39
    end

    def symbol?(c)
      !c.nil? && SYMBOLS.key?(c)
    end

    def space?(c)
      c.nil? || c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12
    end

    # Advance over n code points that contain no newline.
    def bump(n = 1)
      @i += n
      @col += n
    end

    def bump_char
      c = @cs[@i]
      @i += 1
      if c == 10
        @line += 1
        @col = 1
      elsif c == 9
        @col = ((@col - 1) / 8 + 1) * 8 + 1
      else
        @col += 1
      end
    end

    def text(from, to)
      s = ''.dup
      k = from
      to = @cs.length if to > @cs.length
      while k < to
        s << @cs[k]
        k += 1
      end
      s
    end

    def skip_whitespace_and_comments
      loop do
        c = cur
        return if c.nil?

        if space?(c)
          bump_char
        elsif c == 45 && cur(1) == 45 && line_comment?
          bump_char while !cur.nil? && cur != 10
        elsif c == 123 && cur(1) == 45 # {-
          skip_block_comment
        else
          return
        end
      end
    end

    # A run of two or more dashes starts a comment unless the run is part
    # of a longer operator symbol (`-->`, `--|`).
    def line_comment?
      k = @i
      k += 1 while @cs[k] == 45
      c = @cs[k]
      c.nil? || !symbol?(c)
    end

    def skip_block_comment
      line = @line
      col = @col
      pragma = cur(2) == 35 # {-#
      start = @i
      depth = 0
      loop do
        error('unterminated `{-\'', line, col) if cur.nil?
        if cur == 123 && cur(1) == 45
          depth += 1
          bump(2)
        elsif cur == 45 && cur(1) == 125
          depth -= 1
          bump(2)
          break if depth.zero?
        else
          bump_char
        end
      end
      check_pragma(text(start + 3, @i - 2), line, col) if pragma
    end

    # Extensions a LANGUAGE pragma may name: rhci implements them (they are
    # in GHC2021, GHC's default since 9.2, too).
    IMPLEMENTED_EXTENSIONS = %w[BangPatterns].freeze

    # Pragmas are comments to us, except those that change the language:
    # those would silently change semantics, so they are refused.
    def check_pragma(body, line, col)
      body = Rhci::Text.strip(body)
      body = Rhci::Text.strip(body[0..-2]) if body.end_with?('#')
      words = body.split(' ')
      return if words.empty?

      kind = words[0].upcase
      if kind == 'LANGUAGE'
        exts = words[1..-1].join(' ').split(',').map { |e| Rhci::Text.strip(e) }.reject(&:empty?)
        bad = exts.reject { |e| IMPLEMENTED_EXTENSIONS.include?(e) }
        return if bad.empty?

        raise UnsupportedError.new("LANGUAGE pragmas are not supported: #{bad.join(', ')}", line, col, @source)
      end
      return unless kind == 'OPTIONS_GHC' || kind == 'OPTIONS'

      words.each do |w|
        if w.start_with?('-X')
          raise UnsupportedError.new("language options are not supported: #{w}", line, col, @source)
        end
      end
    end

    def emit(kind, start, line, col, value = nil, name = nil, qual = nil)
      bol = line != @last_line
      @last_line = line
      @tokens << Token.new(kind, text(start, @i), line, col, bol, value, name, qual)
    end

    def lex_token
      c = cur
      line = @line
      col = @col
      start = @i
      if c > 127
        raise UnsupportedError.new('non-ASCII characters outside literals and comments are not supported',
                                   line, col, @source)
      end

      if lower?(c)
        bump while ident_char?(cur)
        word = text(start, @i)
        emit(KEYWORDS.key?(word) ? :keyword : :varid, start, line, col)
      elsif upper?(c)
        lex_conid_or_qualified(start, line, col)
      elsif digit?(c)
        lex_number(start, line, col)
      elsif c == 39
        lex_char(start, line, col)
      elsif c == 34
        lex_string(start, line, col)
      elsif SPECIALS.key?(c)
        bump
        emit(:special, start, line, col)
      elsif symbol?(c)
        bump while symbol?(cur)
        sym = text(start, @i)
        emit_symbol(sym, start, line, col, nil)
      else
        error("lexical error at character #{text(@i, @i + 1).inspect}")
      end
    end

    def emit_symbol(sym, start, line, col, qual)
      if qual
        emit(sym.start_with?(':') ? :qconsym : :qvarsym, start, line, col, nil, sym, qual)
      elsif sym == ':'
        emit(:consym, start, line, col)
      elsif sym == '@'
        emit(:reservedop, start, line, col, occurrence(start, @i))
      elsif sym == '!' && occurrence(start, @i) == :prefix
        emit(:bang, start, line, col)
      elsif sym == '~' && occurrence(start, @i) != :prefix
        # Only a prefix `~` is a lazy pattern (proposal 229): `f~(a,b)` and
        # `a ~ b` are the operator.
        emit(:varsym, start, line, col)
      elsif RESERVED_OPS.key?(sym)
        emit(:reservedop, start, line, col)
      elsif sym.start_with?(':')
        emit(:consym, start, line, col)
      else
        emit(:varsym, start, line, col)
      end
    end

    # Whitespace-sensitive operator classification (GHC proposal 229).
    def occurrence(from, to)
      before = from.zero? ? nil : @cs[from - 1]
      after = @cs[to]
      open_before = before.nil? || space?(before) || OPENERS.key?(before)
      closed_after = after.nil? || space?(after) || CLOSERS.key?(after)
      if open_before && !closed_after then :prefix
      elsif !open_before && closed_after then :suffix
      elsif !open_before && !closed_after then :tight
      else :loose
      end
    end

    # Conid, or a qualified name M.x / M.N.Con / M.+ (Report 2.4: no spaces).
    def lex_conid_or_qualified(start, line, col)
      seg_start = @i
      bump while ident_char?(cur)
      loop do
        break unless cur == 46 # '.'

        nxt = cur(1)
        if upper?(nxt)
          bump # '.'
          seg_start = @i
          bump while ident_char?(cur)
        elsif lower?(nxt)
          qual = text(start, @i)
          bump
          name_start = @i
          bump while ident_char?(cur)
          name = text(name_start, @i)
          if KEYWORDS.key?(name)
            # `M.let` is not a qualified name; it is M followed by `.let`.
            @i = name_start - 1
            @col -= name.length + 1
            break
          end
          emit(:qvarid, start, line, col, nil, name, qual)
          return
        elsif symbol?(nxt)
          qual = text(start, @i)
          bump
          sym_start = @i
          bump while symbol?(cur)
          emit_symbol(text(sym_start, @i), start, line, col, qual)
          return
        else
          break
        end
      end
      if seg_start == start
        emit(:conid, start, line, col)
      else
        emit(:qconid, start, line, col, nil, text(seg_start, @i), text(start, seg_start - 1))
      end
    end

    # Digits of `base` with GHC's NumericUnderscores: underscores may only
    # separate digits. Returns [value, digit_count].
    def read_digits(base)
      value = 0
      count = 0
      while digit?(cur, base)
        value = value * base + digit_value(cur)
        count += 1
        bump
        k = 0
        k += 1 while cur(k) == 95
        bump(k) if k > 0 && digit?(cur(k), base)
      end
      [value, count]
    end

    def lex_number(start, line, col)
      if cur == 48 && radix_prefix?
        base = { 120 => 16, 88 => 16, 111 => 8, 79 => 8, 98 => 2, 66 => 2 }[cur(1)]
        bump(2)
        bump while cur == 95
        value, = read_digits(base)
        if base == 16 && hex_float_follows?
          raise UnsupportedError.new('hexadecimal floating-point literals are not supported', line, col, @source)
        end
        emit(:integer, start, line, col, value)
        return
      end

      int_part, = read_digits(10)
      mantissa = int_part
      exp10 = 0
      float = false
      if cur == 46 && digit?(cur(1))
        bump
        frac, frac_digits = read_digits(10)
        mantissa = mantissa * 10**frac_digits + frac
        exp10 = -frac_digits
        float = true
      end
      if (cur == 101 || cur == 69) &&
         (digit?(cur(1)) || ((cur(1) == 43 || cur(1) == 45) && digit?(cur(2))))
        bump
        negative = cur == 45
        bump if cur == 43 || cur == 45
        e, = read_digits(10)
        exp10 += negative ? -e : e
        float = true
      end
      if float
        emit(:float, start, line, col, [mantissa, exp10])
      else
        emit(:integer, start, line, col, mantissa)
      end
    end

    def radix_prefix?
      p = cur(1)
      base = { 120 => 16, 88 => 16, 111 => 8, 79 => 8, 98 => 2, 66 => 2 }[p]
      return false unless base

      k = 2
      k += 1 while cur(k) == 95
      digit?(cur(k), base)
    end

    def hex_float_follows?
      k = 0
      if cur == 46 && digit?(cur(1), 16)
        k = 1
        k += 1 while digit?(cur(k), 16) || cur(k) == 95
      end
      p = cur(k)
      (p == 112 || p == 80) && (digit?(cur(k + 1)) || cur(k + 1) == 45 || cur(k + 1) == 43)
    end

    def lex_char(start, line, col)
      bump # opening '
      c = cur
      if c.nil? || c == 10 || c == 39
        error('lexical error in character literal', line, col)
      end
      value = if c == 92
                bump
                read_escape(false)
              else
                bump_char
                c
              end
      error('lexical error in character literal', line, col) unless cur == 39
      bump
      emit(:char, start, line, col, value)
    end

    def lex_string(start, line, col)
      bump # opening "
      chars = []
      loop do
        c = cur
        error('lexical error in string/character literal at end of input', line, col) if c.nil?
        error('lexical error in string/character literal at character \'\\n\'') if c == 10
        if c == 34
          bump
          break
        elsif c == 92
          bump
          if cur == 38 # \& is empty
            bump
          elsif space?(cur) && !cur.nil?
            skip_string_gap
          else
            chars << read_escape(true)
          end
        else
          chars << c
          bump_char
        end
      end
      emit(:string, start, line, col, chars)
    end

    # Report 2.6: a backslash, whitespace (newlines included), a backslash.
    def skip_string_gap
      bump_char while space?(cur) && !cur.nil?
      error('lexical error in string gap') unless cur == 92
      bump
    end

    # After a backslash: the escaped code point.
    def read_escape(in_string)
      c = cur
      error('lexical error in string/character literal at end of input') if c.nil?
      ch = text(@i, @i + 1)
      if SIMPLE_ESCAPES.key?(ch)
        bump
        return SIMPLE_ESCAPES[ch]
      end
      if c == 94 # \^X control
        x = cur(1)
        if !x.nil? && x >= 64 && x <= 95
          bump(2)
          return x - 64
        end
        error('lexical error in string/character literal')
      end
      if digit?(c)
        return check_range(read_plain_digits(10))
      elsif c == 111 && digit?(cur(1), 8)
        bump
        return check_range(read_plain_digits(8))
      elsif c == 120 && digit?(cur(1), 16)
        bump
        return check_range(read_plain_digits(16))
      end
      ASCII_ESCAPES_BY_LENGTH.each do |name, code|
        next unless text(@i, @i + name.length) == name

        bump(name.length)
        return code
      end
      what = in_string ? 'string/character' : 'character'
      error("lexical error in #{what} literal at character #{ch.inspect}")
    end

    def read_plain_digits(base)
      v = 0
      while digit?(cur, base)
        v = v * base + digit_value(cur)
        bump
      end
      v
    end

    def check_range(v)
      error('numeric escape sequence out of range') if v > MAX_CHAR
      v
    end
  end
end
