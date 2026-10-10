# frozen_string_literal: true

module Rhci
  # A table (name => Name, Name => Scheme, ...) from the Prelude snapshot
  # whose entries need not all be decoded yet. Loaded entries live in a
  # Hash; pending ones are snapshot references, decoded by the loader
  # (Snapshot::Decoder) when looked up -- or all at once, by an operation
  # over the whole table, or by the loader in the background.
  #
  # Deliberately not a Hash: a method this class does not define fails
  # loudly instead of seeing only the loaded part. A plain Hash answers the
  # same methods, so code works with either.
  #
  # The pending entries start as one snapshot record, parsed on the first
  # lookup that misses the loaded ones. Parsed, they are keyed by the key
  # itself, or, for a table keyed by Names (key_core), by Name#core with
  # the key's own reference kept alongside: [key ref, value ref]. A key is
  # never both loaded and pending; writing or deleting a key drops its
  # pending entry.
  class LazyTable
    attr_reader :label, :pending_ref, :pending_count

    def initialize(loaded, loader, key_core, label)
      @h = loaded
      @pending = nil      # Hash, once parsed
      @pending_ref = nil  # the unparsed record
      @pending_count = 0
      @loader = loader
      @key_core = key_core
      @label = label
    end

    # The decoder's second step: count entries are still in record ref.
    def add_pending(ref, count)
      return if count.zero?

      @pending_ref = ref
      @pending_count = count
      @loader.register(self)
    end

    def pending?
      @pending_count.positive?
    end

    def [](k)
      v = @h[k]
      return v if !v.nil? || @pending_count.zero?

      fetch_pending(k)
    end

    def key?(k)
      @h.key?(k) || (@pending_count.positive? && pending.key?(pkey(k)))
    end
    alias include? key?

    def []=(k, v)
      drop_pending(k) if @pending_count.positive?
      @h[k] = v
    end
    alias store []=

    def delete(k)
      v = self[k]
      @h.delete(k)
      v
    end

    def length
      @h.length + @pending_count
    end
    alias size length

    def empty?
      length.zero?
    end

    def dup
      LazyTable.new(@h.dup, @loader, @key_core, @label).copy_pending(self)
    end

    def merge(other)
      t = dup
      other.each { |k, v| t[k] = v }
      t
    end

    def replace(other)
      if other.is_a?(LazyTable)
        @h = other.loaded_entries.dup
        copy_pending(other)
      else
        @h = other.dup
        @pending = nil
        @pending_ref = nil
        @pending_count = 0
      end
      self
    end

    def clear
      @h.clear
      @pending = nil
      @pending_ref = nil
      @pending_count = 0
      self
    end

    # ---- operations over the whole table: everything is loaded first ----

    def each(&block)
      load_all
      @h.each(&block)
    end
    alias each_pair each

    def each_key(&block)
      load_all
      @h.each_key(&block)
    end

    def each_value(&block)
      load_all
      @h.each_value(&block)
    end

    def keys
      load_all
      @h.keys
    end

    def values
      load_all
      @h.values
    end

    def to_h
      load_all
      @h.dup
    end

    # ---- loading ----

    # Decodes up to n pending entries; true once none are left.
    def load_some(n)
      return true if @pending_count.zero?

      keys = []
      pending.each_key do |pk|
        keys << pk
        break if keys.length >= n
      end
      keys.each { |pk| load_entry(pk) }
      @pending_count.zero?
    end

    def load_all
      load_some(@pending_count) while @pending_count.positive?
    end

    # For dup and replace: another table's halves.
    def loaded_entries
      @h
    end

    def parsed_pending
      @pending
    end

    def copy_pending(other)
      @pending = other.parsed_pending&.dup
      @pending_ref = other.pending_ref
      @pending_count = other.pending_count
      @loader.register(self) if @pending_count.positive?
      self
    end

    private

    def pkey(k)
      @key_core ? k.core : k
    end

    def pending
      return @pending if @pending

      @pending = @loader.pending_entries(@pending_ref, @key_core)
      @pending_ref = nil
      @pending
    end

    def drop_pending(k)
      @pending_count -= 1 unless pending.delete(pkey(k)).nil?
    end

    def fetch_pending(k)
      pk = pkey(k)
      return nil unless pending.key?(pk)

      @loader.trace(@label, pk) if @loader.tracing
      load_entry(pk)
    end

    def load_entry(pk)
      entry = @pending.delete(pk)
      @pending_count -= 1
      @loader.entry_loaded
      if @key_core
        k = @loader.value(entry[0])
        v = @loader.value(entry[1])
      else
        k = pk
        v = @loader.value(entry)
      end
      @h[k] = v
    end
  end
end
