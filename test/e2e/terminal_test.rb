# frozen_string_literal: true

require 'pty'
require 'io/console'
require 'tmpdir'

# The REPL on a real terminal (a PTY), for both executables: the line
# editor, history across sessions, Tab completion, and Ctrl-C.
class PtySession
  def initialize(cmd, home)
    @r, @w, @pid = PTY.spawn({ 'HOME' => home }, *cmd)
    @r.winsize = [24, 80]
    @seen = +''
    @mark = 0
  end

  # Send keys, then wait until the output since the last mark contains
  # text. Returns that output.
  def type(keys, until_text, timeout = 30)
    @w.write(keys)
    deadline = Time.now + timeout
    until @seen[@mark..].include?(until_text)
      raise "timed out waiting for #{until_text.inspect}; got #{@seen[@mark..].inspect}" if Time.now > deadline

      ready = @r.wait_readable(0.2)
      begin
        @seen << @r.readpartial(4096) if ready
      rescue EOFError, Errno::EIO
        break
      end
    end
    got = @seen[@mark..]
    @mark = @seen.length
    got
  end

  # Ctrl-D at the prompt; the exit status, or nil if rhci had to be killed.
  # (A Ctrl-D typed while rhci evaluates reaches a terminal in cooked mode,
  # where it is an end-of-file for a read nobody makes, and is lost.)
  def close
    return @status if @closed

    @closed = true
    type('', "rhci> \e[K", 10) unless @seen.end_with?("rhci> \e[K")
    @w.write("\x04")
    deadline = Time.now + 10
    while Time.now < deadline
      done = Process.wait(@pid, Process::WNOHANG)
      return @status = $?.exitstatus if done

      sleep 0.05
    end
    Process.kill('KILL', @pid)
    Process.wait(@pid)
    nil
  rescue Errno::ECHILD
    nil
  end
end

EXECUTABLES.each do |label, cmd|
  RT.suite "terminal #{label}" do
    RT.test 'editing, completion, history, Ctrl-C' do
      Dir.mktmpdir do |home|
        s = PtySession.new(cmd, home)
        begin
          terminal_session(s, home)
        ensure
          s.close
        end
        s = PtySession.new(cmd, home)
        begin
          s.type('', 'rhci> ')
          RT.ok s.type("\e[A\r", "42\r").include?('6*7'), 'history survives the session'
        ensure
          s.close
        end
      end
    end
  end
end

# Line ends are \r\n (CRuby's raw mode) or \r\r\n (mruby's keeps output
# processing on), so waits look for "\r" plus what follows.
def terminal_session(s, home)
  s.type('', 'rhci> ')
  RT.ok s.type("1+1\r", "\n2\r").include?("\n2\r"), 'evaluates'
  RT.ok s.type("putStrL\t", 'putStrLn ').include?('putStrLn '), 'completes'
  RT.ok s.type("\"hi\"\r", "\nhi\r").include?("\nhi\r"), 'runs the completed line'
  RT.ok s.type("\e[A\e[A\r", "\n2\r").include?('1+1'), 'recalls history'
  s.type("length [1..]\r", "\n")
  sleep 0.5
  RT.ok s.type("\x03", 'Interrupted.').include?('Interrupted.'), 'interrupts evaluation'
  s.type("getLine\r", "\n")
  sleep 0.3
  RT.ok s.type("\x03", 'Interrupted.').include?('Interrupted.'), 'interrupts a blocked read'
  RT.ok s.type("abc\x03", '^C').include?('^C'), 'Ctrl-C abandons the line'
  RT.ok s.type("6*7\r", "\n42\r").include?("\n42\r"), 'still alive'
  RT.ok s.type(":load oracle/files/Geo\t", 'Geometry.hs ').include?('Geometry.hs '), 'completes paths'
  s.type("\x15", "rhci> \e[K")
  RT.eq 0, s.close
  RT.eq "1+1\nputStrLn \"hi\"\n1+1\nlength [1..]\ngetLine\n6*7\n", File.read(File.join(home, '.rhci_history'))
end
