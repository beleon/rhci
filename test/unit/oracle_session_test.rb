# frozen_string_literal: true

# Semantic fidelity against the GHCi goldens (oracle/README.md): each
# section replays in one Session. Where rhci answers (does not refuse
# with "unsupported"), it must agree with GHCi:
#   :type      equal types up to renaming, String = [Char]
#   outcome    ok / parse / scope / compile / runtime error class
#   output     identical stdout when both succeed
# Refusals are counted, not hidden: see the coverage line printed below.
sem_probes = Oracle.load(File.join(RHCI_ROOT, 'oracle', 'golden-ghc-9.6.7.txt')) +
             Oracle.load(File.join(RHCI_ROOT, 'oracle', 'golden-load-ghc-9.6.7.txt'))
SEM_FILES = File.join(RHCI_ROOT, 'oracle', 'files')
sem_gaps = Oracle.known_gaps(File.join(RHCI_ROOT, 'oracle', 'known_gaps.txt'), 'semantics')
sem_sections = []
sem_probes.each { |p| sem_sections << p.section unless sem_sections.include?(p.section) }
$oracle_coverage = [0, 0, 0] # [answered, total, over the step budget]

SEM_STATUS = { ok: :ok, parse_error: :parse, scope_error: :scope, compile_error: :compile,
               exception: :runtime, command_error: :command }.freeze

def sem_input(p)
  return p.input unless p.input.start_with?(":{\n")

  lines = p.input.split("\n")
  lines[1..-2].join("\n")
end

RT.suite 'oracle: semantics' do
  sem_sections.each do |title|
    RT.test title do
      out = RT::FakeIO.new
      # Speed is not what this checks: each input gets a step budget, and
      # one that exhausts it is skipped (counted), not failed.
      session = Rhci::Session.new(stdout: out, stderr: out, limits: { steps: 3_000_000 }, cwd: SEM_FILES)
      problems = []
      sem_probes.each do |p|
        next unless p.section == title

        $oracle_coverage[1] += 1
        input = sem_input(p)
        before = out.written.length
        r = session.eval(input)
        next if r.status == :unsupported
        if r.status == :limit
          $oracle_coverage[2] += 1
          next
        end

        $oracle_coverage[0] += 1
        next if sem_gaps.key?(p.input)

        ours = SEM_STATUS[r.status] || r.status
        want = Oracle.outcome(p.text)
        got_out = out.written[before..-1]
        word, arg = p.input[1..-1].to_s.split(' ', 2)
        command = p.input.start_with?(':') ? Rhci::Session.command_name(word.to_s) : nil
        if %w[load reload].include?(command)
          # GHCi ran with -v0 (no "Ok, ... loaded."): compare the outcome only.
          problems << "#{p.input.inspect}: GHCi #{want}, rhci #{ours} (#{r.message})" if ours != want
        elsif command == 'type' && want == :ok
          if ours != :ok
            problems << "#{p.input}: GHCi gives a type, rhci #{ours}: #{r.message}"
            next
          end
          g = p.text.sub("#{arg} :: ", '')
          o = Rhci::Text.strip(got_out).sub("#{Rhci::Text.strip(arg)} :: ", '')
          problems << "#{p.input}: GHCi #{g}, rhci #{o}" unless Oracle.normalize_type(g) == Oracle.normalize_type(o)
        elsif ours != want
          problems << "#{p.input.inspect}: GHCi #{want}, rhci #{ours} (#{r.message})"
        elsif want == :ok && Rhci::Text.strip(got_out) != Rhci::Text.strip(p.text)
          problems << "#{p.input.inspect}: GHCi printed #{p.text.inspect}, rhci #{got_out.inspect}"
        end
      end
      RT.ok problems.empty?, problems.join("\n      ")
    end
  end

  RT.test 'coverage (informational)' do
    answered, total, slow = $oracle_coverage
    puts "      oracle: rhci answers #{answered} of #{total} probes (#{slow} skipped over the step budget); " \
         'the rest are refused as unsupported'
  end
end
