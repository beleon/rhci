# frozen_string_literal: true

require 'open3'
require 'fileutils'
require 'tmpdir'

# The same command-line cases against every executable: the CRuby launcher,
# the compact CRuby build (one file, snapshot embedded) and the mruby
# binary. Their behaviour must be identical.
ROOT = File.expand_path('../..', __dir__)
EXECUTABLES = {
  'CRuby bin/rhci' => [RbConfig.ruby, File.join(ROOT, 'bin', 'rhci')],
  'CRuby compact build/rhci.rb' => [RbConfig.ruby, File.join(ROOT, 'build', 'rhci.rb')],
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

    RT.test '-c writes a String result raw; -x runs an IO action' do
      RT.eq ['Hello', '', 0], run_exe(cmd, ['-c', '"Hello"'])
      RT.eq ["hi λ\n", '', 0], run_exe(cmd, ['-x', 'putStrLn "hi \\955"'])
      _, err, code = run_exe(cmd, ['-c', 'putStrLn "x"'])
      RT.eq 3, code
      RT.ok err.include?('use rhci -x'), err
    end

    RT.test 'readFile, writeFile, appendFile: errors, locks, decoding (as GHCi)' do
      script = "writeFile \"a\" \"x\\n\"\nappendFile \"a\" \"y\"\nreadFile \"a\"\ns <- readFile \"a\"\n" \
               "writeFile \"a\" \"\"\nlength s\nwriteFile \"a\" \"z\"\nreadFile \"a\"\nreadFile \"bad.txt\"\n" \
               "readFile \"none\"\nreadFile \"dir\"\nwriteFile \"dir/../dir\" \"q\"\nlines <$> readFile \"text.txt\"\n"
      Dir.mktmpdir('rhci-e2e') do |dir|
        FileUtils.cp_r(File.join(ROOT, 'oracle', 'files_io', '.'), dir)
        out, err, status = Open3.capture3(*cmd, stdin_data: script, chdir: dir)
        RT.eq 0, status.exitstatus
        RT.eq "rhci> rhci> rhci> \"x\\ny\"\nrhci> rhci> rhci> 3\nrhci> rhci> \"z\"\nrhci> \"abrhci> rhci> rhci> rhci> " \
              "[\"line one\",\"\\955\\8594x\",\"last\"]\nrhci> \n", out
        RT.eq "*** Exception: a: withFile: resource busy (file is locked)\n" \
              "*** Exception: bad.txt: hGetContents: invalid argument (cannot decode byte sequence starting from 255)\n" \
              "*** Exception: none: openFile: does not exist (No such file or directory)\n" \
              "*** Exception: dir: openFile: inappropriate type (is a directory)\n" \
              "*** Exception: dir/../dir: withFile: inappropriate type (Is a directory)\n", err
      end
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
      out, err, code = run_exe(cmd, [], ":{\nlet a = \"x\"\n    b = a\n:}\nputStrLn b\n:qu\n")
      RT.eq 0, code
      RT.eq "rhci> rhci| rhci| rhci| rhci> x\nrhci> ", out
      RT.eq '', err
    end

    RT.test 'unknown commands; :t parses its argument' do
      out, err, = run_exe(cmd, [], ":foo\n:t 1 +\n:t 'x'\n")
      RT.eq "unknown command ':foo'\nuse :? for help.\n" \
            "<interactive>:1:4: parse error (possibly incorrect indentation or mismatched brackets)\n", err
      RT.ok out.include?("'x' :: Char\n"), out
    end

    RT.test 'stdin: -i, getArgs, getLine prompts, UTF-8 input, stderr' do
      RT.eq ["HÉ Λ\nX", '', 0], run_exe(cmd, ['-i', '-c', 'map toUpper'], "hé λ\nx")
      RT.eq ["Name: hi λ\n", '', 0],
            run_exe(cmd, ['-x', 'putStr "Name: " >> getLine >>= \\n -> putStrLn ("hi " ++ n)'], "λ\n")
      RT.eq ["one\ntwo three\n", '', 0], run_exe(cmd, ['-x', 'getArgs >>= mapM_ putStrLn', 'one', 'two three'])
      RT.eq ['', "e\n", 0], run_exe(cmd, ['-x', 'hPutStrLn stderr "e"'])
      _, err, code = run_exe(cmd, ['-x', 'getLine'])
      RT.eq 1, code
      RT.ok err.include?('<stdin>: hGetLine: end of file'), err
    end
  end
end
