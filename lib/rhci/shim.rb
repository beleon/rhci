# frozen_string_literal: true

module Rhci
  # The one place allowed to know which Ruby it runs on. Everything else
  # talks to IO objects only through these methods, so the core needs
  # nothing beyond `gets`, `write` and `flush` from them (tests substitute
  # a fake; mruby has no StringIO).
  module Shim
    MRUBY = RUBY_ENGINE == 'mruby'

    # Monotonic seconds, or nil where there is no clock (lean mruby).
    def self.now
      return nil if MRUBY

      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Contents of a file, or nil if it does not exist.
    def self.read_file(path)
      return nil unless File.exist?(path)

      File.read(path)
    end

    # The rhci binary's C helpers (mrbgems/rhci/src/term.c); absent in the
    # plain mruby that runs the test bundle.
    TERM = MRUBY && Rhci.const_defined?(:Term) ? Rhci::Term : nil

    # Raised by the CRuby SIGINT trap into a blocked stdin read.
    class Interrupted < StandardError; end

    # The file descriptor behind io when rhci reads it itself (the mruby
    # binary's stdin, unbuffered, so a SIGINT can end a blocked read).
    def self.own_fd(io)
      TERM && io.equal?($stdin) ? 0 : nil
    end

    # A line including its newline, nil at end of input, or :interrupt.
    def self.read_line(io)
      return io.gets unless own_fd(io)

      line = ''.dup
      loop do
        c = read_char(io)
        return :interrupt if c == :interrupt
        return(line.empty? ? nil : line) if c.nil?

        line << c
        return line if c == "\n"
      end
    end

    # One character (a String) from io, nil at end of input, or :interrupt
    # when Ctrl-C ended a blocked read. mruby's getc may return single
    # bytes of a UTF-8 sequence; they are joined.
    def self.read_char(io)
      if own_fd(io)
        b = TERM.read_byte(0)
        return nil if b.nil?
        return :interrupt if b == -1

        return utf8_char(b) { TERM.read_byte(0) }
      end
      c = getc(io)
      return c if c.nil? || c == :interrupt || !MRUBY

      b = c.getbyte(0)
      return c if b < 0x80 || c.bytesize > 1

      utf8_char(b) do
        d = io.getc
        d&.getbyte(0)
      end
    end

    def self.getc(io)
      return io.getc if MRUBY

      begin
        @reading = true
        c = io.getc
        @reading = false
        c
      rescue Interrupted
        @reading = false
        :interrupt
      end
    end

    # The character whose UTF-8 encoding starts with byte b; more bytes
    # come from the block.
    def self.utf8_char(b)
      return ''.dup << b if b < 0x80

      extra = if b >= 0xF0 then 3
              elsif b >= 0xE0 then 2
              else 1
              end
      cp = b & (0x3F >> extra)
      extra.times do
        d = yield
        break if d.nil? || d < 0

        cp = (cp << 6) | (d & 0x3F)
      end
      ''.dup << cp
    end

    # ---- the interactive terminal (CLI only; never used by the library) ----

    def self.fd_of(io)
      if io.equal?($stdin) then 0
      elsif io.equal?($stdout) then 1
      elsif io.equal?($stderr) then 2
      end
    end

    def self.tty?(io)
      return io.respond_to?(:tty?) && io.tty? unless MRUBY

      fd = fd_of(io)
      !TERM.nil? && !fd.nil? && TERM.tty?(fd)
    end

    # Key-at-a-time input without echo; Ctrl-C arrives as byte 3.
    def self.raw_mode(io)
      if MRUBY
        TERM.raw(0)
      else
        require 'io/console'
        @console_mode ||= io.console_mode
        io.raw!(intr: false)
      end
    end

    def self.cooked_mode(io)
      if MRUBY
        TERM.restore
      elsif @console_mode
        io.console_mode = @console_mode
        @console_mode = nil
      end
    end

    # One byte from the terminal (raw mode), or nil at end of input.
    def self.read_byte(io)
      return io.getbyte unless MRUBY

      b = TERM.read_byte(0)
      b == -1 ? 3 : b
    end

    def self.term_width(io)
      return TERM.width(1) if MRUBY

      require 'io/console'
      begin
        w = io.winsize[1]
        w.positive? ? w : 80
      rescue StandardError
        80
      end
    end

    # Ctrl-C during evaluation: CRuby runs the block in a trap (it may raise
    # Interrupted into a blocked read, see getc); mruby only sets a flag,
    # which the machine polls through interrupt_pending?.
    def self.trap_interrupt(&on_signal)
      if MRUBY
        TERM&.trap_sigint
      else
        Signal.trap('INT') do
          raise Interrupted if @reading

          on_signal.call
        end
      end
    end

    def self.interrupt_pending?
      !TERM.nil? && TERM.take_sigint
    end

    def self.getenv(name)
      MRUBY ? TERM&.getenv(name) : ENV.fetch(name, nil)
    end

    # The names in a directory, or nil.
    def self.dir_entries(path)
      return TERM&.entries(path) if MRUBY
      return nil unless Dir.exist?(path)

      Dir.children(path)
    end

    def self.append_file(path, text)
      File.open(path, 'a') { |f| f.write(text) }
      nil
    end

    # ---- files for readFile/writeFile/appendFile ----------------------------
    # The failure is classified by inspecting the path, the same way on
    # both runtimes (mruby's lean build has no Errno classes): :enoent,
    # :enotdir, :eisdir or :eacces.

    # A file's bytes (an Array of Integers), or a failure Symbol.
    def self.read_bytes(path)
      why = path_problem(path, false)
      return why if why

      File.open(path, 'rb') { |f| f.read }.bytes
    rescue StandardError
      :eacces
    end

    # Truncates (or, appending, creates) the file; nil or a failure Symbol.
    def self.open_for_write(path, append)
      why = path_problem(path, true)
      return why if why

      File.open(path, append ? 'ab' : 'wb') { |_| nil }
      nil
    rescue StandardError
      :eacces
    end

    def self.append_bytes(path, str)
      File.open(path, 'ab') { |f| f.write(str) }
      nil
    end

    # The canonical name of an existing file (what GHC's per-file lock is
    # keyed on), or nil.
    def self.real_path(path)
      File.realpath(path)
    rescue StandardError
      nil
    end

    def self.path_problem(path, writing)
      return :enoent if path.empty?

      parts = path.split('/')
      prefix = path.start_with?('/') ? '/' : ''
      i = 0
      while i < parts.length - 1
        part = parts[i]
        i += 1
        next if part.empty?

        prefix += part
        return :enoent unless File.exist?(prefix)
        return :enotdir unless File.directory?(prefix)

        prefix += '/'
      end
      return :eisdir if File.directory?(path)
      return :enoent if !writing && !File.exist?(path)

      nil
    end

    def self.write(io, str)
      io.write(str)
      nil
    end

    def self.flush(io)
      io.flush
      nil
    end
  end
end
