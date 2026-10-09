# frozen_string_literal: true

# Prints the Core of Prelude globals whose names match the arguments
# (substring), or of an expression with -e. A development aid.
#   ruby tools/dump_core.rb sum enumFromTo
#   ruby tools/dump_core.rb -e 'map (*3) [1..10]'
ROOT = File.expand_path('..', __dir__)
require File.join(ROOT, 'lib', 'rhci')

module CorePrinter
  def self.show(e, ind = 0)
    pad = '  ' * ind
    case e
    when Rhci::Core::Var then e.name
    when Rhci::Core::Lit then e.value.inspect
    when Rhci::Core::Str then e.cps.pack('U*').inspect
    when Rhci::Core::App then "(#{show(e.fn, ind)} #{e.args.map { |a| show(a, ind) }.join(' ')})"
    when Rhci::Core::Lam then "(\\#{e.params.join(' ')} ->\n#{pad}  #{show(e.body, ind + 1)})"
    when Rhci::Core::Let
      bs = e.binds.map { |n, r| "#{pad}  #{n} = #{show(r, ind + 2)}" }.join("\n")
      "let\n#{bs}\n#{pad}in #{show(e.body, ind)}"
    when Rhci::Core::Case
      alts = e.alts.map do |a|
        key = a.kind == :con ? ([a.key.name] + a.vars.map { |v| v || '_' }).join(' ') : (a.kind == :lit ? a.key.inspect : '_')
        "#{pad}  #{key} -> #{show(a.body, ind + 2)}"
      end.join("\n")
      "case #{show(e.scrut, ind)} of#{e.binder ? " #{e.binder}@" : ''}\n#{alts}"
    when Rhci::Core::Con then "[#{e.con.name}#{e.args.map { |a| ' ' + show(a, ind) }.join}]"
    when Rhci::Core::Prim then "{#{e.op} #{e.args.map { |a| show(a, ind) }.join(' ')}}"
    else e.inspect
    end
  end
end

captured = []
s = Rhci::Session.new(prelude: :source)
Rhci::Lower.prepend(Module.new do
  define_method(:global_value) do |name, core|
    captured << [name, core]
    super(name, core)
  end
end)
s.eval('1')
if ARGV[0] == '-e'
  captured.clear
  s.eval("rhci_dump = #{ARGV[1]}")
  captured.each { |n, c| puts "#{n} =\n  #{CorePrinter.show(c, 1)}\n\n" }
else
  captured.each do |n, c|
    next unless ARGV.any? { |a| n.include?(a) }

    puts "#{n} =\n  #{CorePrinter.show(c, 1)}\n\n"
  end
end
