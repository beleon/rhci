# frozen_string_literal: true

# Front-end fidelity against real GHCi: rhci must report a parse error
# exactly where GHCi does, and parse everything else (later stages decide
# whether it type-checks and what it prints).
probes = Oracle.load(File.join(RHCI_ROOT, 'oracle', 'golden-ghc-9.6.7.txt'))
gaps = Oracle.known_gaps(File.join(RHCI_ROOT, 'oracle', 'known_gaps.txt'), 'frontend')

def frontend_outcome(src)
  if src.is_a?(Array)
    Rhci::Frontend.parse_expression(src[1])
  else
    Rhci::Frontend.parse_repl(src)
  end
  :parsed
rescue Rhci::Error => e
  e.kind == :parse ? :parse : (e.kind == :unsupported ? :unsupported : :parsed)
end

sections = []
probes.each { |p| sections << p.section unless sections.include?(p.section) }

RT.suite 'oracle: front end' do
  sections.each do |title|
    RT.test title do
      problems = []
      probes.each do |p|
        next unless p.section == title

        src = p.frontend_input
        next if src.nil?

        want = p.ghci_class
        got = frontend_outcome(src)
        next if want == got || gaps.key?(p.input)

        problems << "#{p.input.inspect}: GHCi #{want}, rhci #{got}"
      end
      RT.ok problems.empty?, problems.join("\n      ")
    end
  end
end
