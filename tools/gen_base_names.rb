# frozen_string_literal: true

# Regenerates lib/rhci/base_names.rb from GHCi's own `:browse` of the base
# and containers modules rhci knows. CRuby-only tool (needs podman).
#
#   DEFAULT_MODULES  in scope at the prompt without an import (their names
#                    do not clash); BASE_VALUES / BASE_TYPES list them
#   IMPORTABLE       known modules reached only by `import` or qualified
#                    names (Data.Map clashes with the Prelude, say)
#
# MODULE_EXPORTS lists every known module's own exports, for qualified
# names and imports. A listed name rhci does not define yet is reported as
# "not implemented yet", never as "not in scope".
ROOT = File.expand_path('..', __dir__)
DEFAULT_MODULES = %w[Prelude Data.List Data.Maybe Data.Char Data.Tuple Data.Function Data.Ord Data.Either
                     Control.Monad System.IO System.Environment Text.Read Data.Bits Data.Ratio Data.IORef
                     Text.Printf].freeze
IMPORTABLE = %w[Data.Map Data.Map.Strict Data.Set Data.Foldable Data.Traversable Data.Functor Control.Applicative
                Data.Bool Data.Monoid Data.String Numeric Data.Word Data.Int Control.Exception].freeze

# One GHCi run per module, with the Prelude hidden, so that every name of
# the module prints unqualified.
def browse(mod)
  script = "import Prelude ()\nimport #{mod}\n:browse #{mod}\n"
  IO.popen(['podman', 'run', '--rm', '-i', 'docker.io/library/haskell:9.6', 'sh', '-c',
            'ghci -ignore-dot-ghci -v0 2>&1'], 'r+') do |io|
    io.write(script)
    io.close_write
    io.read
  end
end

# M.x or M.+ (a module prefix), as opposed to an operator such as `.`.
def qualified?(name)
  i = name.index('.')
  !i.nil? && i.positive? && name[0] >= 'A' && name[0] <= 'Z'
end

# [values, types] a module exports, in :browse order.
def exports(text)
  values = []
  types = []
  # Join `data` declarations continued on indented `=`/`|` lines, and
  # records continued while a brace is open.
  lines = []
  text.split("\n").each do |line|
    open = !lines.empty? && lines[-1].count('{') > lines[-1].count('}')
    if !lines.empty? && (open || line.start_with?('  = ') || line.start_with?('  | '))
      lines[-1] = "#{lines[-1]} #{line.strip}"
    else
      lines << line
    end
  end
  lines.each do |line|
    next if line.include?('{-#')

    if (m = line.match(/\A\s*(\(.+?\)|[a-z_][A-Za-z0-9_']*) ::/))
      name = m[1]
      name = name[1..-2] if name.start_with?('(')
      values << name unless qualified?(name) || values.include?(name)
    elsif (m = line.match(/\Atype ([A-Z][A-Za-z0-9_']*) ::/))
      types << m[1] unless types.include?(m[1])
    elsif (m = line.match(/\A(?:data|newtype) [^=]*= (.*)\z/))
      m[1].split(' | ').each do |alt|
        con = alt.strip.sub(/\Aforall [^.]*\.\s*/, '').split(/[ {]/).first
        next if con.nil?

        con = con[1..-2] if con.start_with?('(')
        values << con unless con.include?('.') || con.include?('#') || values.include?(con)
        record_fields(alt).each { |f| values << f unless values.include?(f) }
      end
    end
  end
  [values, types]
end

# The field names of a constructor written with record syntax.
def record_fields(alt)
  i = alt.index('{') or return []
  depth = 0
  body = +''
  alt[i..].each_char do |c|
    depth += 1 if '({['.include?(c)
    depth -= 1 if ')}]'.include?(c)
    break if depth.zero?

    body << c if depth >= 1
  end
  parts = [+'']
  depth = 0
  body[1..].to_s.each_char do |c|
    depth += 1 if '([{'.include?(c)
    depth -= 1 if ')]}'.include?(c)
    c == ',' && depth.zero? ? parts << +'' : parts[-1] << c
  end
  parts.map { |p| p.split('::')[0].strip }.select { |n| n.match?(/\A[a-z_][A-Za-z0-9_']*\z/) }
end

# Every module GHC's installed packages expose: an import of one rhci does
# not know is unsupported, not "not found".
def ghc_modules
  out = IO.popen(['podman', 'run', '--rm', 'docker.io/library/haskell:9.6', 'sh', '-c',
                  "ghc-pkg field '*' exposed-modules --simple-output"], &:read)
  # Re-exports read "M from pkg-1.0:M,": keep the plain module names.
  out.split(/[\s,]+/).reject { |m| m.empty? || m == 'from' || m.include?(':') }.uniq.sort
end

module_exports = {}
(DEFAULT_MODULES + IMPORTABLE).each do |mod|
  text = browse(mod)
  raise "#{mod}: #{text[0, 300]}" if text.include?('Could not find module') || text.include?('<interactive>:')

  module_exports[mod] = exports(text)
  warn "#{mod}: #{module_exports[mod][0].length} values, #{module_exports[mod][1].length} types"
end

values = {}
types = {}
DEFAULT_MODULES.each do |mod|
  vs, ts = module_exports[mod]
  vs.each { |v| values[v] ||= mod }
  ts.each { |t| types[t] ||= mod }
end

def ruby_hash(h)
  h.keys.sort.map { |k| "    #{k.inspect} => #{h[k].inspect}," }.join("\n")
end

def ruby_list(a)
  a.map(&:inspect).each_slice(8).map { |s| "        #{s.join(', ')}" }.join(",\n")
end

exports_src = module_exports.map do |mod, (vs, ts)|
  "    #{mod.inspect} => [\n      [\n#{ruby_list(vs)}\n      ],\n      [\n#{ruby_list(ts)}\n      ]\n    ]"
end.join(",\n")

File.write(File.join(ROOT, 'lib', 'rhci', 'base_names.rb'), <<~RUBY)
  # frozen_string_literal: true

  # GENERATED by tools/gen_base_names.rb from GHCi's `:browse` -- do not edit.
  module Rhci
    # rhci's own Haskell library modules (prelude/Data/...), compiled after
    # the Prelude in this order, and which of them implement each public
    # module (Data.Map.Strict falls back to the lazy Data.Map).
    LIBRARY_MODULES = %w[Data.Set.Internal Data.Map.Internal Data.Map.Strict.Internal].freeze
    LIBRARY_IMPLEMENTATIONS = {
      'Data.Set' => %w[Data.Set.Internal], 'Data.Map' => %w[Data.Map.Internal],
      'Data.Map.Strict' => %w[Data.Map.Strict.Internal Data.Map.Internal]
    }.freeze

    # The modules in scope at the prompt without an import.
    DEFAULT_MODULES = #{DEFAULT_MODULES.inspect}.freeze

    # Every value and type name of the default modules, with the first
    # module (in DEFAULT_MODULES order) that exports it.
    BASE_VALUES = {
  #{ruby_hash(values)}
    }.freeze

    BASE_TYPES = {
  #{ruby_hash(types)}
    }.freeze

    # Every known module's exports: name => [values, types].
    MODULE_EXPORTS = {
  #{exports_src}
    }.freeze

    # Every module GHC's installed packages expose (ghc-pkg).
    GHC_MODULES = %w[
  #{ghc_modules.each_slice(6).map { |s| "    #{s.join(' ')}" }.join("\n")}
    ].freeze
  end
RUBY
puts "#{values.length} default values, #{types.length} default types, #{module_exports.length} modules"
