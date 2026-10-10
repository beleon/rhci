# frozen_string_literal: true

# The snapshot's lazily decoded tables (LazyTable) and the session's
# loading of what startup left pending: on demand, while idle, and in the
# background while inputs run. (The mruby test bundle embeds a snapshot
# whose entries are all pending, so every other test on mruby exercises
# loading on demand too.)

# A tiny snapshot, two records per chunk: the root is [table, Name-keyed
# table]; table has "a" => 1 loaded and "b" => 2, "c" => [3] pending; the
# Name-keyed one has x%7 => 5 pending.
LAZY_SNAP = [
  "rhci-snapshot\t2\t2\t9\t2\t9",
  "A\tr1\tr4\nL\tt\tF\t1\t2\tsa\ti1\tr2",
  "P\tsb\ti2\tsc\tr3\nA\ti3",
  "L\tn\tT\t0\t1\tr5\nP\tx%7\tr6\ti5",
  "O\tRhci::Name\t@str\tsx\t@uid\ti7\t@kind\tyvar\nA",
  "A"
].freeze

def lazy_roots
  d = Rhci::Snapshot.decoder(LAZY_SNAP)
  [d, d.root]
end

def lazy_snapshot_session(**opts)
  text = snap_text
  return nil unless text

  # Loaded at once, so the process-wide setting can be put back (other
  # tests compile the Prelude from source on CRuby).
  Rhci::Session.snapshot_text = text
  out = RT::FakeIO.new
  s = Rhci::Session.new(stdout: out, stderr: out, prelude: :snapshot, **opts)
  s.eval('()')
  out.written.clear
  [s, out]
ensure
  Rhci::Session.snapshot_text = nil
end

RT.suite 'lazy snapshot tables' do
  RT.test 'a lookup decodes a pending entry; length counts pending ones' do
    d, (t, _) = lazy_roots
    RT.eq 3, t.length
    RT.eq 1, t['a']
    RT.eq 3, d.pending_count, 'b and c here, x%7 in the other table'
    RT.eq [3], t['c']
    RT.eq 2, d.pending_count
    RT.ok t.key?('b') && !t.key?('z'), 'key? sees pending entries'
    RT.eq nil, t['z']
    RT.eq 3, t.length
  end

  RT.test 'writing or deleting a key drops its pending entry; dups are independent' do
    _, (t, _) = lazy_roots
    copy = t.dup
    t['b'] = 20
    RT.eq 20, t['b']
    RT.eq 2, copy['b']
    RT.eq [3], t.delete('c')
    RT.eq nil, t['c']
    RT.eq [3], copy['c']
    RT.eq 2, t.length
    RT.eq 3, copy.length
    t.replace(copy)
    RT.eq 2, t['b']
  end

  RT.test 'operations over the whole table load it first' do
    _, (t, _) = lazy_roots
    RT.eq %w[a b c], t.keys.sort
    got = {}
    t.each { |k, v| got[k] = v }
    RT.eq({ 'a' => 1, 'b' => 2, 'c' => [3] }, got)
  end

  RT.test 'a Name-keyed table finds its pending entries by the Name' do
    d, (_, n) = lazy_roots
    RT.eq 1, n.length
    RT.ok d.load_step(nil), 'load_step(nil) loads everything'
    RT.eq 0, d.pending_count
    key = n.keys[0]
    RT.eq ['x', 7, 5], [key.str, key.uid, n[key]]
  end
end

RT.suite 'loading the Prelude snapshot' do
  RT.test 'idle time loads everything; the session is unchanged by it' do
    s, out = lazy_snapshot_session
    RT.ok s, 'no snapshot available (run rake bundle)'
    s.eval('1 + 1')
    RT.ok s.loading?, 'entries are still pending after one input'
    polls = 0
    s.load_while_idle(-> { (polls += 1) > 1_000_000 })
    RT.ok !s.loading?, 'everything is loaded'
    s.eval('Data.Map.toList (Data.Map.fromList [(2, "b"), (1, "a")])')
    s.eval(':t foldr')
    RT.eq "2\n[(1,\"a\"),(2,\"b\")]\nfoldr :: Foldable c => (a -> b -> b) -> b -> c a -> b\n", out.written
  end

  RT.test 'idle loading stops as soon as input is waiting' do
    s, = lazy_snapshot_session
    s.eval('1')
    before = s.pending_entries
    s.load_while_idle(-> { true })
    RT.eq before, s.pending_entries
  end

  RT.test 'background loading proceeds while an input runs (a session option)' do
    input = 'length (show (product [1 .. 3000 :: Integer]))'
    plain, = lazy_snapshot_session
    plain.eval(input)
    s, out = lazy_snapshot_session
    s.background_loading = true
    s.instance_variable_set(:@preload_time, 0.0) # lint:ok (a test pacing the loader)
    s.eval(input)
    RT.ok s.loaded_entries > plain.loaded_entries + 100,
          "background loading loaded more (#{plain.loaded_entries} -> #{s.loaded_entries})"
    RT.eq "9131\n", out.written
  end

  RT.test ':load undoes the instances a session added' do
    s, out = lazy_snapshot_session
    s.eval('data T = T')
    s.eval('instance Show T where show _ = "t"')
    s.eval('T')
    s.eval(':load nofile')
    s.eval('show (Just 1)')
    RT.eq "t\n\"Just 1\"\n", out.written
  end
end
