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
  end
end
