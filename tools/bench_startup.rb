# frozen_string_literal: true

# Startup budgets (docs/ARCHITECTURE.md §6), measured on this machine:
#   interactive: time from spawn until the prompt is on the terminal < 10 ms
#   rhci -c EXPR: whole process, spawn to exit                      < 200 ms
# Medians over several runs; exits non-zero when a budget is exceeded.
require 'pty'
require 'io/wait'

EXE = ARGV.fetch(0)
PROMPT = 'rhci> '
RUNS = 30

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def median(xs)
  s = xs.sort
  s[s.length / 2]
end

def time_to_prompt
  t0 = now
  PTY.spawn(EXE) do |r, w, pid|
    seen = +''
    until seen.include?(PROMPT)
      raise "no prompt within 5 s (got #{seen.inspect})" unless r.wait_readable(5)

      seen << r.readpartial(4096)
    end
    elapsed = now - t0
    w.write(":q\n")
    Process.wait(pid)
    return elapsed
  end
end

def time_command(*args)
  t0 = now
  pid = Process.spawn(EXE, *args, out: File::NULL, err: File::NULL)
  Process.wait(pid)
  now - t0
end

def report(label, samples, budget)
  m = median(samples)
  ok = m < budget
  printf("%-28s median %7.2f ms  max %7.2f ms  budget %4d ms  %s\n", # lint:ok (CRuby-only tool)
         label, m * 1000, samples.max * 1000, (budget * 1000).round, ok ? 'ok' : 'OVER BUDGET')
  ok
end

prompt = Array.new(RUNS) { time_to_prompt }
cmd = Array.new(RUNS) { time_command('-c', '"Hello"') }
ok = report('interactive prompt', prompt, 0.010)
ok = report('rhci -c \'"Hello"\'', cmd, 0.200) && ok
exit(ok ? 0 : 1)
