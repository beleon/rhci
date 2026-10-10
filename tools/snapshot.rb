# frozen_string_literal: true

# Compiles the Prelude and encodes the resulting session state for
# Rhci::Snapshot (format documented in lib/rhci/snapshot.rb). CRuby-only
# build tool; tools/bundle.rb embeds its output in the mruby binary.
#
#   ruby tools/snapshot.rb OUT [ON_DEMAND_OUT]
#
# The core -- the table entries decoded at startup -- is what the inputs in
# tools/snapshot_corpus.txt look up: they run against a snapshot with every
# entry pending, and the entries they load are traced. ON_DEMAND_OUT gets
# that all-pending snapshot (the mruby test bundle uses it, so every test
# also checks that a lookup finds what is not yet loaded).
require_relative '../lib/rhci'

module SnapshotEncoder
  # Instance variables that only compile time needs (or caches).
  DROP = {
    'Rhci::Name' => %i[@field_types],
    'Rhci::NameEnv' => %i[@module_tables],
    'Rhci::ClassInfo' => %i[@tok @sigs @context_ast],
    'Rhci::InstInfo' => %i[@tok @type_ast @context_ast @super_evs @binds_full],
    'Rhci::RBind' => %i[@eqs @pat @rhs @names @sigs @tok @deps @dicts @signed],
    'Rhci::AST::TCon' => %i[@tok @ty @groups @ev],
    'Rhci::AST::TVar' => %i[@tok @ty @groups @ev @ref],
    'Rhci::AST::TApp' => %i[@tok @ty @groups @ev @ref],
    'Rhci::AST::TFun' => %i[@tok @ty @groups @ev @ref],
    'Rhci::AST::TList' => %i[@tok @ty @groups @ev @ref],
    'Rhci::AST::TTuple' => %i[@tok @ty @groups @ev @ref],
    'Rhci::AST::TQual' => %i[@tok @ty @groups @ev]
  }.freeze

  CHUNK = 256 # records per chunk

  # A lazy table's pending entries, encoded as their own "P" record.
  Pending = Struct.new(:table)

  # roots: Session#prelude_state. core: label => {key => true} (Name#core
  # for Name-keyed tables), the entries to decode at startup. hot: objects
  # in the order the corpus first used them; their code comes first, so an
  # input's code sits in few chunks. Returns the text and the objects in
  # record order.
  def self.encode(roots, core, hot = [])
    Rhci::Snapshot.register_classes
    @singles = {}.compare_by_identity
    Rhci::Snapshot.singletons.each { |k, v| @singles[v] = k }
    @lazy = lazy_tables(roots)
    @core = core
    @pending = {}.compare_by_identity
    order = arrange(roots, hot)
    ids = {}.compare_by_identity
    order.each_with_index { |o, i| ids[o] = i }
    ref = ->(o) { literal(o) || "r#{ids.fetch(o) { raise "snapshot: #{o.class} not arranged" }}" }
    records = order.map { |o| record(o, ref) }
    n1 = order.index { |o| @phase[o] > 1 } || order.length
    n2 = order.index { |o| @phase[o] > 2 } || order.length
    chunks = records.each_slice(CHUNK).map { |c| c.join("\n") }
    [(["rhci-snapshot\t2\t#{CHUNK}\t#{records.length}\t#{n1}\t#{n2}"] + chunks).join("\f"), order]
  end

  # Hash => [label, keyed by Names?] for the tables decoded entry by entry.
  def self.lazy_tables(roots)
    names, tenv, globals, unfoldings, full_cores, specs = roots
    t = {}.compare_by_identity
    t[tenv] = ['tenv', true]
    t[globals] = ['globals', false]
    t[unfoldings] = ['unfoldings', false]
    t[full_cores] = ['full_cores', false]
    t[specs] = ['specs', false]
    %i[@values @types @internal @base_values @base_types].each do |iv|
      h = names.instance_variable_get(iv)
      t[h] = ["names#{iv}", false] if h
    end
    (names.instance_variable_get(:@library) || {}).each do |m, tables|
      t[tables[:values]] = ["library:#{m}:values", false]
      t[tables[:types]] = ["library:#{m}:types", false]
    end
    t
  end

  # Every object, in record order: the core run (phase 1), the rest of the
  # tables' structure (2), compiled code (3). Each run is breadth-first.
  def self.arrange(roots, hot)
    @phase = {}.compare_by_identity
    later = { 2 => [], 3 => [] }
    out = []
    [1, 2, 3].each do |p|
      start = { 1 => [roots], 2 => later[2], 3 => hot + later[3] }[p]
      queue = []
      start.each do |o|
        next if @phase.key?(o)

        @phase[o] = p
        queue << o
      end
      i = 0
      while i < queue.length
        o = queue[i]
        i += 1
        out << o
        children(o) do |c, cp|
          next if literal(c) || @phase.key?(c)

          cp = p if cp < p
          if cp == p
            @phase[c] = p
            queue << c
          else
            later[cp] << c
          end
        end
      end
    end
    out
  end

  # Yields [child, phase it belongs to at the earliest].
  def self.children(o)
    case o
    when Hash
      unless @lazy[o]
        o.each do |k, v|
          yield k, 1
          yield v, 1
        end
        return
      end
      now, later = split_table(o)
      now.each do |k, v|
        yield k, 1
        yield v, 1
      end
      yield pending_marker(o), 2 unless later.empty?
    when Pending
      _, later = split_table(o.table)
      later.each do |k, v|
        yield k, 2 if @lazy[o.table][1]
        yield v, 2
      end
    when Array then o.each { |x| yield x, 1 }
    else
      @lazy[o.instance_variable_get(:@instances)] ||= ["instances:#{o.name.core}", false] if o.is_a?(Rhci::ClassInfo)
      ivars(o).each { |iv| yield o.instance_variable_get(iv), (o.class == Rhci::VM::Cell && iv == :@value ? 3 : 1) }
    end
  end

  # A lazy table's entries: [core ones, pending ones].
  def self.split_table(h)
    label, key_core = @lazy[h]
    core = @core[label] || {}
    h.partition { |k, _| core.key?(key_core ? k.core : k) }
  end

  def self.pending_marker(h)
    @pending[h] ||= Pending.new(h)
  end

  def self.ivars(o)
    o.instance_variables - (DROP[o.class.name] || [])
  end

  def self.literal(o)
    case o
    when nil then 'n'
    when true then 'T'
    when false then 'F'
    when Integer then "i#{o}"
    when Float then "f#{Rhci::Num.double_to_bits(o).to_s(16)}"
    when Symbol then "y#{o}"
    when String then "s#{escape(o)}"
    else @singles.key?(o) ? "K#{@singles[o]}" : nil
    end
  end

  def self.record(o, ref)
    case o
    when Hash
      lazy = @lazy[o]
      return (['H'] + o.flat_map { |k, v| [ref.call(k), ref.call(v)] }).join("\t") unless lazy

      label, key_core = lazy
      now, later = split_table(o)
      fields = ['L', escape(label), key_core ? 'T' : 'F', now.length.to_s, later.length.to_s]
      now.each { |k, v| fields.push(ref.call(k), ref.call(v)) }
      fields.push(later.empty? ? 'n' : ref.call(pending_marker(o)))
      fields.join("\t")
    when Pending
      label, key_core = @lazy[o.table]
      _, later = split_table(o.table)
      fields = ['P']
      later.each do |k, v|
        if key_core
          fields.push(escape(k.core), ref.call(k), ref.call(v))
        else
          raise "snapshot: table #{label} has a non-literal key #{k.inspect[0, 60]}" unless literal(k)

          fields.push(ref.call(k), ref.call(v))
        end
      end
      fields.join("\t")
    when Array
      return (['A'] + o.map { |x| ref.call(x) }).join("\t") if o.class == Array

      check(o)
      (['B', o.class.name] + o.map { |x| ref.call(x) }).join("\t")
    else
      check(o)
      (['O', o.class.name] + ivars(o).flat_map { |iv| [iv.to_s, ref.call(o.instance_variable_get(iv))] }).join("\t")
    end
  end

  def self.check(o)
    return if Rhci::Snapshot::CLASSES.key?(o.class.name)

    raise "snapshot: unexpected #{o.class} (#{o.inspect[0, 80]}) -- compile-time data leaking?"
  end

  def self.escape(s)
    s.gsub('\\') { '\\\\' }.gsub("\n", '\\n').gsub("\t", '\\t').gsub("\f", '\\f')
  end

  # What the corpus uses, each line in a fresh session (a line may hold
  # several inputs, separated by " ;; "): the table entries looked up (the
  # core), and the objects decoded, in first-use order. order: the objects
  # of text in record order.
  def self.train(text, order, corpus)
    core = {}
    hot = []
    seen = {}
    sink = Object.new
    def sink.write(s) = s.length
    def sink.flush = nil
    Rhci::Session.snapshot_text = text
    corpus.each do |line|
      session = Rhci::Session.new(stdout: sink, stderr: sink, prelude: :snapshot, limits: { steps: 2_000_000 })
      session.trace_snapshot = true
      line.split(' ;; ').each { |input| session.eval(input) }
      session.snapshot_trace.each { |label, key| (core[label] ||= {})[key] = true }
      session.snapshot_decoded.each do |i|
        next if seen.key?(i)

        seen[i] = true
        hot << order[i] unless order[i].is_a?(Pending)
      end
    end
    Rhci::Session.snapshot_text = nil
    [core, hot]
  end
end

if __FILE__ == $PROGRAM_NAME
  session = Rhci::Session.new
  session.send(:load_prelude)
  state = session.send(:prelude_state)
  on_demand, order = SnapshotEncoder.encode(state, {})
  corpus_path = File.join(__dir__, 'snapshot_corpus.txt')
  corpus = File.read(corpus_path).split("\n").reject { |l| l.strip.empty? || l.start_with?('#') }
  core, hot = SnapshotEncoder.train(on_demand, order, corpus)
  text, = SnapshotEncoder.encode(state, core, hot)
  File.write(ARGV.fetch(0), text)
  File.write(ARGV[1], on_demand) if ARGV[1]
  head = text[0, text.index("\f")].split("\t")
  puts "#{head[3]} records, #{text.bytesize} bytes; core #{head[4]} records, structure #{head[5]}"
end
