# frozen_string_literal: true

# Compiles the Prelude and encodes the resulting session state for
# Rhci::Snapshot.decode (format documented there). CRuby-only build tool;
# tools/bundle.rb embeds its output in the mruby binary.
require_relative '../lib/rhci'

module SnapshotEncoder
  # Instance variables that only compile time needs.
  DROP = {
    'Rhci::Name' => %i[@field_types],
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

  def self.encode(roots)
    Rhci::Snapshot.register_classes
    singles = {}.compare_by_identity
    Rhci::Snapshot.singletons.each { |k, v| singles[v] = k }
    ids = {}.compare_by_identity
    queue = []
    ref = lambda do |o|
      case o
      when nil then 'n'
      when true then 'T'
      when false then 'F'
      when Integer then "i#{o}"
      when Float then "f#{Rhci::Num.double_to_bits(o).to_s(16)}"
      when Symbol then "y#{o}"
      when String then "s#{escape(o)}"
      else
        next "K#{singles[o]}" if singles.key?(o)

        unless ids.key?(o)
          ids[o] = queue.length
          queue << o
        end
        "r#{ids[o]}"
      end
    end
    ref.call(roots)
    out = []
    i = 0
    while i < queue.length
      o = queue[i]
      out << case o
             when Hash then (['H'] + o.flat_map { |k, v| [ref.call(k), ref.call(v)] }).join("\t")
             when Array
               if o.class == Array
                 (['A'] + o.map { |x| ref.call(x) }).join("\t")
               else
                 check(o)
                 (['B', o.class.name] + o.map { |x| ref.call(x) }).join("\t")
               end
             else
               check(o)
               drop = DROP[o.class.name] || []
               ivs = o.instance_variables - drop
               (['O', o.class.name] + ivs.flat_map { |iv| [iv.to_s, ref.call(o.instance_variable_get(iv))] }).join("\t")
             end
      i += 1
    end
    out.join("\n")
  end

  def self.check(o)
    return if Rhci::Snapshot::CLASSES.key?(o.class.name)

    raise "snapshot: unexpected #{o.class} (#{o.inspect[0, 80]}) -- compile-time data leaking?"
  end

  def self.escape(s)
    s.gsub('\\') { '\\\\' }.gsub("\n", '\\n').gsub("\t", '\\t')
  end
end

if __FILE__ == $PROGRAM_NAME
  session = Rhci::Session.new
  session.send(:load_prelude)
  text = SnapshotEncoder.encode(session.send(:prelude_state))
  File.write(ARGV.fetch(0), text)
  puts "#{text.count("\n") + 1} records, #{text.bytesize} bytes"
end
