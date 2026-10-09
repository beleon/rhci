# frozen_string_literal: true

require 'open3'

# The same command-line cases against both executables: the CRuby launcher
# and the mruby binary. Their behaviour must be identical.
ROOT = File.expand_path('../..', __dir__)
EXECUTABLES = {
  'CRuby bin/rhci' => [RbConfig.ruby, File.join(ROOT, 'bin', 'rhci')],
  'mruby binary' => [File.join(ROOT, 'build', 'rhci', 'bin', 'rhci')]
}.freeze

def run_exe(cmd, args, stdin = '')
  out, err, status = Open3.capture3(*cmd, *args, stdin_data: stdin)
  [out, err, status.exitstatus]
end

EXECUTABLES.each do |label, cmd|
  RT.suite "e2e #{label}" do
    RT.test '--version' do
      RT.eq ["rhci #{Rhci::VERSION}\n", '', 0], run_exe(cmd, ['--version'])
    end

    RT.test 'usage error exits 2' do
      _, err, code = run_exe(cmd, ['-c'])
      RT.eq 2, code
      RT.ok err.start_with?('rhci: -c requires an expression'), err
    end

    RT.test '-c is refused explicitly until implemented' do
      RT.eq ['', "unsupported: evaluation is not implemented yet\n", 4], run_exe(cmd, ['-c', '"Hello"'])
    end

    RT.test 'REPL quits on :q' do
      RT.eq [Rhci::CLI::PROMPT, '', 0], run_exe(cmd, [], ":q\n")
    end

    RT.test 'parse errors are reported with location and exit 3' do
      _, err, code = run_exe(cmd, ['-c', '1 +'])
      RT.eq 3, code
      RT.eq "<interactive>:1:4: parse error (possibly incorrect indentation or mismatched brackets)\n", err
      _, err, code = run_exe(cmd, ['-c', '(+)', '3 - -2'])
      RT.eq 3, code
      RT.ok err.include?('cannot mix'), err
    end

    RT.test ':{ :} groups lines with their layout; :qu abbreviates :quit' do
      out, err, code = run_exe(cmd, [], ":{\nlet a = 1\n    b = 2\n:}\n:qu\n")
      RT.eq 0, code
      RT.eq 'rhci> rhci| rhci| rhci| rhci> ', out
      RT.eq "unsupported: evaluation is not implemented yet\n", err
    end

    RT.test 'unknown commands; :t parses its argument' do
      _, err, = run_exe(cmd, [], ":foo\n:t 1 +\n:t 1\n")
      RT.eq "unknown command ':foo'\nuse :? for help.\n" \
            "<interactive>:1:4: parse error (possibly incorrect indentation or mismatched brackets)\n" \
            "unsupported: type inference is not implemented yet\n", err
    end
  end
end
