# frozen_string_literal: true

# The REPL line editor through a fake terminal: keys in, screen writes out.
class LeTerm
  attr_reader :out

  def initialize(keys, width = 80)
    @bytes = []
    keys.each_byte { |b| @bytes << b }
    @out = ''.dup
    @width = width
  end

  def read_byte
    @bytes.shift
  end

  def write(str)
    @out << str
  end

  attr_reader :width
end

def le_read(keys, history: [], completer: nil, width: 80, pending: nil)
  term = LeTerm.new(keys, width)
  ed = Rhci::LineEditor.new(term, history: history, completer: completer)
  [ed.read_line('> ', pending), term.out, ed]
end

RT.suite 'line editor' do
  RT.test 'typing, Enter, UTF-8 input' do
    RT.eq 'abc', le_read("abc\r")[0]
    RT.eq "λx", le_read("λx\r")[0]
    RT.eq 'ab', le_read("ab\n")[0]
  end

  RT.test 'cursor movement and deletion' do
    RT.eq 'xabc', le_read("abc\x01x\r")[0]            # Ctrl-A, insert
    RT.eq 'abxc', le_read("abc\e[Dx\r")[0]            # Left
    RT.eq 'abcx', le_read("abc\e[D\e[Cx\r")[0]        # Left, Right
    RT.eq 'ab', le_read("abc\x7f\r")[0]               # Backspace
    RT.eq 'bc', le_read("abc\x01\e[3~\r")[0]          # Home, Delete
    RT.eq 'bc', le_read("abc\eOH\x04\r")[0]           # Home (SS3), Ctrl-D deletes
    RT.eq 'a', le_read("abc\x01\x06\x0b\r")[0]        # Ctrl-F, Ctrl-K
    RT.eq 'c', le_read("abc\x02\x15\r")[0]            # Ctrl-B, Ctrl-U
    RT.eq 'foo ', le_read("foo bar\x17\r")[0]         # Ctrl-W
    RT.eq 'X foo bar', le_read("foo bar\eb\ebX \r")[0] # Meta-b twice
    RT.eq 'foo Xbar', le_read("foo bar\e[1;5DX\r")[0]     # Ctrl-Left
    RT.eq 'fooX bar', le_read("foo bar\x01\e[1;5CX\r")[0] # Ctrl-Right
  end

  RT.test 'Ctrl-C abandons the line; Ctrl-D on an empty line is end of input' do
    line, out, = le_read("abc\x03")
    RT.eq :interrupt, line
    RT.ok out.end_with?("^C\r\n"), out.inspect
    RT.eq nil, le_read("\x04")[0]
    RT.eq nil, le_read('')[0]
  end

  RT.test 'history: up and down, the edited line is kept' do
    hist = %w[one two]
    RT.eq 'two', le_read("\e[A\r", history: hist.dup)[0]
    RT.eq 'one', le_read("\e[A\e[A\e[A\r", history: hist.dup)[0]
    RT.eq 'new', le_read("new\e[A\e[B\r", history: hist.dup)[0]
    RT.eq 'one', le_read("\x10\x10\r", history: hist.dup)[0]
    _, _, ed = le_read("three\r", history: hist.dup)
    RT.eq %w[one two three], ed.history
    _, _, ed = le_read("two\r", history: hist.dup)
    RT.eq %w[one two], ed.history
  end

  RT.test 'Tab completes the common prefix, then lists' do
    completer = lambda do |before|
      space = before.rindex(' ')
      start = space ? space + 1 : 0
      word = before[start..-1]
      [start, %w[putStr putStrLn print].select { |w| w.start_with?(word) }]
    end
    RT.eq 'print ', le_read("pri\t\r", completer: completer)[0]
    RT.eq 'putStr', le_read("pu\t\r", completer: completer)[0]
    line, out, = le_read("putStr\t\t\r", completer: completer)
    RT.eq 'putStr', line
    RT.ok out.include?("putStr    putStrLn\r\n"), out.inspect
    RT.eq 'x', le_read("x\t\r", completer: completer)[0]
  end

  RT.test 'pending input from a look-ahead starts the line' do
    RT.eq 'abc', le_read("bc\r", pending: 'a')[0]
  end

  RT.test 'a long line scrolls; the screen row never exceeds the width' do
    line, out, = le_read("#{'x' * 50}\r", width: 20)
    RT.eq 'x' * 50, line
    rows = out.split("\r").map { |r| r.sub("\e[K", '') }
    RT.ok rows.all? { |r| r.length < 20 }, rows.inspect
  end
end

RT.suite 'REPL completion' do
  RT.test 'names in scope, commands, files' do
    s = Rhci::Session.new
    s.eval('myValue = 3')
    RT.eq [0, %w[myValue]], s.completions('myV')
    st, names = s.completions('putStrL')
    RT.eq [0, %w[putStrLn]], [st, names]
    RT.eq [4, %w[maybe]], [s.completions('map maybe')[0], s.completions('map maybe')[1] & %w[maybe]]
    RT.eq [1, %w[load]], s.completions(':lo')
    RT.eq [1, %w[reload]], s.completions(':re')
    RT.eq [0, []], s.completions('')
    RT.ok s.completions('Mayb')[1].include?('Maybe'), s.completions('Mayb').inspect
    RT.ok s.completions('rhci_')[1].empty?, 'internal names stay hidden'
  end

  # Directory listing needs Dir (CRuby) or the rhci binary's C helpers;
  # the plain mruby that runs this bundle has neither (the terminal e2e
  # test covers the binary).
  RT.test ':load completes paths' do
    next if Rhci::Shim.dir_entries('.').nil?

    s = Rhci::Session.new(cwd: File.join(RHCI_ROOT, 'oracle', 'files'))
    st, names = s.completions(':load Geo')
    RT.eq [6, %w[Geometry.hs]], [st, names]
    RT.eq %w[Data/], s.completions(':l Da')[1]
    RT.eq %w[Data/Stack.hs], s.completions(':l Data/S')[1]
  end
end
