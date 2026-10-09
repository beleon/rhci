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

    def self.read_line(io)
      io.gets
    end

    # One character (a String) from io, or nil at end of input. mruby's
    # getc may return single bytes of a UTF-8 sequence; they are joined.
    def self.read_char(io)
      c = io.getc
      return nil if c.nil?
      return c unless MRUBY

      b = c.getbyte(0)
      return c if b < 0x80 || c.bytesize > 1

      extra = if b >= 0xF0 then 3
              elsif b >= 0xE0 then 2
              else 1
              end
      bytes = c.dup
      extra.times do
        d = io.getc
        break if d.nil?

        bytes << d
      end
      bytes
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
