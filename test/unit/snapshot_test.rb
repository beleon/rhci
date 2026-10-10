# frozen_string_literal: true

# The build-time Prelude snapshot must behave exactly like compiling
# prelude/Prelude.hs: same output for the same inputs, both ways round.
SNAP_INPUTS = [
  '1 + 2', '2 ^ 64', '10 / 3', '"hé\\n"', "'x'", 'Just (-3)', '[1.5, 2]', 'show (Just "x")',
  ':t foldr', ':t (+)', 'data C = R | G | B deriving (Show, Eq, Ord, Enum, Bounded)', '[R ..]',
  'maxBound :: C', 'sort [3, 1, 2]', 'words "a b  c"', 'fmap (+1) (Just 2)', 'mapM_ print [1, 2]',
  'let fibs = 0 : 1 : zipWith (+) fibs (tail fibs) in fibs !! 50', 'head []', 'Just (-0.0)'
].freeze

def snap_text
  return Rhci::Session.embedded_snapshot if Rhci::Session.embedded_snapshot

  path = File.join(RHCI_ROOT, 'build', 'prelude.snapshot')
  File.exist?(path) ? File.read(path) : nil
end

def snap_run(mode)
  out = RT::FakeIO.new
  s = Rhci::Session.new(stdout: out, prelude: mode)
  results = SNAP_INPUTS.map do |i|
    r = s.eval(i)
    [r.status, r.message]
  end
  [out.written, results]
end

RT.suite 'prelude snapshot' do
  RT.test 'a snapshot session behaves like a compiled one' do
    text = snap_text
    RT.ok text, 'no snapshot available (run rake bundle)'
    Rhci::Session.snapshot_text = text
    begin
      RT.eq snap_run(:source), snap_run(:snapshot)
    ensure
      Rhci::Session.snapshot_text = nil
    end
  end
end
