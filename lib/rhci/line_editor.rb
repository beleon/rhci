# frozen_string_literal: true

module Rhci
  # The REPL's line editor: Emacs-style keys, history and Tab completion,
  # on any terminal that sends VT100/xterm key sequences. It talks to the
  # terminal only through `term` (read_byte, write, width), so tests drive
  # it with a fake; LineEditor::Tty is the real one.
  #
  # A line is edited on one screen row: when it is wider than the terminal,
  # the row scrolls horizontally to keep the cursor visible.
  class LineEditor
    # The terminal behind the CLI's stdin/stdout, in raw mode while a line
    # is edited.
    class Tty
      def initialize(input, output)
        @input = input
        @output = output
      end

      def raw
        Shim.raw_mode(@input)
      end

      def cooked
        Shim.cooked_mode(@input)
      end

      def read_byte
        Shim.read_byte(@input)
      end

      # Is a byte waiting to be read?
      def ready?
        Shim.input_ready?(@input)
      end

      def write(str)
        Shim.write(@output, str)
        Shim.flush(@output)
      end

      def width
        Shim.term_width(@output)
      end
    end

    HISTORY_MAX = 1000

    attr_reader :history, :term

    # completer: called with the text before the cursor; returns
    # [start, candidates], where start is where the word being completed
    # begins (a character index) and candidates are its completions.
    # idle: called before waiting for each key (the REPL loads the Prelude
    # meanwhile).
    def initialize(term, history: [], completer: nil, idle: nil)
      @term = term
      @history = history
      @completer = completer
      @idle = idle
    end

    # The next line (without newline), nil at end of input (Ctrl-D on an
    # empty line), or :interrupt (Ctrl-C). pending: characters already
    # typed (handed back by the REPL's stdin look-ahead).
    def read_line(prompt, pending = nil)
      @prompt = prompt
      @buf = []
      @pos = 0
      @hist_pos = @history.length
      @scratch = nil
      @last_tab = false
      @offset = 0
      insert_text(pending) if pending
      refresh
      loop do
        @idle&.call
        b = @term.read_byte
        return eof if b.nil?

        tab = false
        case b
        when 13, 10
          finish
          line = @buf.join
          remember(line)
          return line
        when 3
          finish('^C')
          return :interrupt
        when 4
          return eof if @buf.empty?

          delete_at_cursor
        when 1 then move_to(0)
        when 5 then move_to(@buf.length)
        when 2 then move_to(@pos - 1)
        when 6 then move_to(@pos + 1)
        when 8, 127 then backspace
        when 11 then kill(@pos, @buf.length)
        when 21 then kill(0, @pos)
        when 23 then kill(word_start(@pos), @pos)
        when 12
          @term.write("\e[H\e[2J")
          refresh
        when 16 then history_move(-1)
        when 14 then history_move(1)
        when 9
          complete
          tab = true
        when 27 then escape
        else
          insert_char(utf8(b)) if b >= 32
        end
        @last_tab = tab
      end
    end

    private

    # End of input; the REPL ends the prompt's row itself.
    def eof
      nil
    end

    def finish(mark = '')
      move_to(@buf.length)
      @term.write("#{mark}\r\n")
    end

    def remember(line)
      return if Text.blank?(line) || @history.last == line

      @history << line
      @history.shift while @history.length > HISTORY_MAX
    end

    # A character from its first byte, reading continuation bytes.
    def utf8(b)
      Shim.utf8_char(b) { @term.read_byte }
    end

    def insert_text(text)
      text.each_char do |c|
        @buf.insert(@pos, c)
        @pos += 1
      end
    end

    def insert_char(c)
      @buf.insert(@pos, c)
      @pos += 1
      refresh
    end

    def delete_at_cursor
      return if @pos >= @buf.length

      @buf.delete_at(@pos)
      refresh
    end

    def backspace
      return if @pos.zero?

      @pos -= 1
      @buf.delete_at(@pos)
      refresh
    end

    def kill(from, to)
      return if from >= to

      @buf.slice!(from, to - from)
      @pos = from
      refresh
    end

    def move_to(pos)
      pos = 0 if pos.negative?
      pos = @buf.length if pos > @buf.length
      @pos = pos
      refresh
    end

    def word_char?(c)
      AST.ident_start?(c) || (c >= '0' && c <= '9') || c == "'" || c == '_'
    end

    def word_start(pos)
      pos -= 1 while pos.positive? && !word_char?(@buf[pos - 1])
      pos -= 1 while pos.positive? && word_char?(@buf[pos - 1])
      pos
    end

    def word_end(pos)
      pos += 1 while pos < @buf.length && !word_char?(@buf[pos])
      pos += 1 while pos < @buf.length && word_char?(@buf[pos])
      pos
    end

    def history_move(delta)
      target = @hist_pos + delta
      return if target.negative? || target > @history.length

      @scratch = @buf.join if @hist_pos == @history.length
      @hist_pos = target
      line = target == @history.length ? @scratch.to_s : @history[target]
      @buf = []
      @pos = 0
      insert_text(line)
      refresh
    end

    # ESC sequences: arrows, Home/End/Delete (CSI and SS3 forms), and
    # Meta-b / Meta-f. Unknown sequences are read to their end and ignored.
    def escape
      b = @term.read_byte
      return if b.nil?

      case b
      when 98 then move_to(word_start(@pos)) # M-b
      when 102 then move_to(word_end(@pos))  # M-f
      when 91, 79
        params = ''.dup
        final = @term.read_byte
        while final && (final < 64 || final > 126)
          params << final
          final = @term.read_byte
        end
        csi(params, final) if final
      end
    end

    def csi(params, final)
      ctrl = params.end_with?(';5')
      case final
      when 65 then history_move(-1) # up
      when 66 then history_move(1)  # down
      when 67 then move_to(ctrl ? word_end(@pos) : @pos + 1)
      when 68 then move_to(ctrl ? word_start(@pos) : @pos - 1)
      when 72 then move_to(0)            # Home
      when 70 then move_to(@buf.length)  # End
      when 126
        case params
        when '1', '7' then move_to(0)
        when '4', '8' then move_to(@buf.length)
        when '3' then delete_at_cursor
        end
      end
    end

    # Tab: complete to the candidates' longest common prefix (a unique
    # candidate also gets a space); a second Tab lists them.
    def complete
      return unless @completer

      before = @buf[0, @pos].join
      start, candidates = @completer.call(before)
      return if candidates.nil? || candidates.empty?

      word = before[start..-1] || ''
      common = common_prefix(candidates)
      if common.length > word.length
        insert_text(common[word.length..-1])
        insert_text(' ') if candidates.length == 1 && @pos == @buf.length && !common.end_with?('/')
        refresh
      elsif candidates.length == 1
        insert_text(' ') if @pos == @buf.length && !common.end_with?('/')
        refresh
      elsif @last_tab
        list(candidates)
      end
    end

    def common_prefix(words)
      first = words[0]
      n = first.length
      words.each do |w|
        i = 0
        i += 1 while i < n && i < w.length && w[i] == first[i]
        n = i
      end
      first[0, n]
    end

    def list(candidates)
      width = @term.width
      col = candidates.map(&:length).max + 2
      per_row = [width / col, 1].max
      out = "\r\n".dup
      candidates.sort.each_slice(per_row) do |row|
        out << Text.rstrip(row.map { |c| c + (' ' * (col - c.length)) }.join) << "\r\n"
      end
      @term.write(out)
      @offset = 0
      refresh
    end

    # Redraw the row: prompt, the visible part of the line, cursor placed.
    def refresh
      width = @term.width
      room = width - @prompt.length - 1
      room = 1 if room < 1
      @offset = @pos if @pos < @offset
      @offset = @pos - room if @pos - @offset > room
      @offset = 0 if @offset.negative?
      visible = @buf[@offset, room] || []
      out = "\r#{@prompt}#{visible.join}\e[K".dup
      back = visible.length - (@pos - @offset)
      out << "\e[#{back}D" if back.positive?
      @term.write(out)
    end
  end
end
