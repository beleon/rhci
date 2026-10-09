# frozen_string_literal: true

# Minimal test framework that runs unchanged on CRuby and mruby (which has
# no minitest, StringIO or Time). Tests are registered at load time and run
# by RT.run, which returns true when everything passed.
module RT
  class Failure < StandardError; end

  @tests = []
  @suite = nil

  def self.suite(name)
    outer = @suite
    @suite = outer ? "#{outer} / #{name}" : name
    yield
  ensure
    @suite = outer
  end

  def self.test(name, &block)
    @tests << [@suite, name, block]
  end

  def self.eq(expected, actual, what = nil)
    return if expected == actual

    label = what ? "#{what}: " : ''
    raise Failure, "#{label}expected #{expected.inspect}, got #{actual.inspect}"
  end

  def self.ok(cond, message)
    raise Failure, message unless cond
  end

  # The `kind` of the Rhci::Error the block raises, or nil. (mruby leaves
  # `$!` nil inside a `rescue` modifier, so tests must not rely on it.)
  def self.error_kind
    yield
    nil
  rescue Rhci::Error => e
    e.kind
  end

  def self.raises(klass)
    begin
      yield
    rescue klass => e
      return e
    end
    raise Failure, "expected #{klass} to be raised"
  end

  def self.run
    failures = []
    @tests.each do |suite, name, block|
      begin
        block.call
      rescue Exception => e # rubocop:disable Lint/RescueException
        failures << ["#{suite}: #{name}", e]
      end
    end
    failures.each do |label, e|
      kind = e.is_a?(Failure) ? 'FAIL' : "ERROR #{e.class}"
      puts "#{kind}  #{label}\n      #{e.message}"
    end
    puts "#{RUBY_ENGINE}: #{@tests.length} tests, #{failures.length} failures"
    failures.empty?
  end

  # Stand-in for an IO object: the core only ever calls gets/write/flush.
  class FakeIO
    attr_reader :written

    # log/tag: writes are also appended to log as "tag:text", so a test
    # can see how writes to several fakes interleave.
    def initialize(input = '', log: nil, tag: nil)
      @log = log
      @tag = tag
      @input = input
      @pos = 0
      @written = ''.dup
    end

    def gets
      return nil if @pos >= @input.length
      stop = @input.index("\n", @pos)
      stop = stop.nil? ? @input.length : stop + 1
      line = @input[@pos, stop - @pos]
      @pos = stop
      line
    end

    def getc
      return nil if @pos >= @input.length
      @pos += 1
      @input[@pos - 1]
    end

    def write(str)
      @log << "#{@tag}:#{str}" if @log
      @written << str
      str.length
    end

    def flush
      self
    end
  end
end
