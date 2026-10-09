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
