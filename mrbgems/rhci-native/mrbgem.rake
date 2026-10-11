# rhci's native helpers, in both mruby builds (so the mruby test run uses
# them too): the terminal and process helpers (src/term.c) and the C
# evaluation loop (src/machine.c).
MRuby::Gem::Specification.new('rhci-native') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Leon Becker'
  spec.summary = 'rhci native helpers: terminal and the evaluation loop'
end
