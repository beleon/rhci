# frozen_string_literal: true

RT.suite 'CLI' do
  RT.test 'no arguments starts the REPL' do
    o = Rhci::CLI.parse([])
    RT.eq :repl, o.action
    RT.eq [], o.files
  end

  RT.test 'positional arguments are files to load' do
    RT.eq ['A.hs', 'B.hs'], Rhci::CLI.parse(['A.hs', 'B.hs']).files
  end

  RT.test '-c takes EXPR and every remaining argument, flag-like or not' do
    o = Rhci::CLI.parse(['-c', '(+)', '3 :: Double', '-5'])
    RT.eq [:run, :pure, '(+)'], [o.action, o.mode, o.expr]
    RT.eq ['3 :: Double', '-5'], o.args
  end

  RT.test '-x selects IO mode; -i must come before it' do
    o = Rhci::CLI.parse(['-i', '-x', 'getArgs >>= print', 'a'])
    RT.eq [:io, true, ['a']], [o.mode, o.interact, o.args]
  end

  RT.test 'usage errors' do
    RT.raises(Rhci::CLI::UsageError) { Rhci::CLI.parse(['-c']) }
    RT.raises(Rhci::CLI::UsageError) { Rhci::CLI.parse(['-q']) }
    RT.raises(Rhci::CLI::UsageError) { Rhci::CLI.parse(['-i']) }
  end

  RT.test 'main reports usage errors with exit status 2' do
    err = RT::FakeIO.new
    RT.eq 2, Rhci::CLI.main(['-c'], stdin: RT::FakeIO.new, stdout: RT::FakeIO.new, stderr: err)
    RT.ok err.written.include?('-c requires an expression'), err.written
  end

  RT.test 'REPL prompts, quits on :q, and exits 0 on EOF' do
    out = RT::FakeIO.new
    RT.eq 0, Rhci::CLI.main([], stdin: RT::FakeIO.new(":q\n"), stdout: out, stderr: RT::FakeIO.new)
    RT.eq Rhci::CLI::PROMPT, out.written
    RT.eq 0, Rhci::CLI.main([], stdin: RT::FakeIO.new(''), stdout: RT::FakeIO.new, stderr: RT::FakeIO.new)
  end

  RT.test '-c prints a String result raw' do
    out = RT::FakeIO.new
    RT.eq 0, Rhci::CLI.main(['-c', '"Hello\\n"'], stdin: RT::FakeIO.new, stdout: out, stderr: RT::FakeIO.new)
    RT.eq "Hello\n", out.written
  end

  RT.test 'what needs type classes is refused explicitly until implemented (exit 4)' do
    err = RT::FakeIO.new
    RT.eq 4, Rhci::CLI.main(['-c', '[1, 2]'], stdin: RT::FakeIO.new, stdout: RT::FakeIO.new, stderr: err)
    RT.ok err.written.start_with?('unsupported: '), err.written
  end

  RT.test 'files given to the REPL are not silently ignored' do
    err = RT::FakeIO.new
    RT.eq 0, Rhci::CLI.main(['Foo.hs'], stdin: RT::FakeIO.new(":q\n"), stdout: RT::FakeIO.new, stderr: err)
    RT.eq "unsupported: :load is not implemented yet\n", err.written
  end
end
