# frozen_string_literal: true

# Where the C evaluation loop exists (the mruby builds), it must behave
# exactly like the Ruby one: same output, same errors, same step counts.
NATIVE_INPUTS = [
  'sum [1..2000]', 'let fib :: Int -> Int; fib n = if n < 2 then n else fib (n-1) + fib (n-2) in fib 15',
  'take 5 (map show [1..])', 'let x = x + 1 in x :: Int', '2^100 + 1', 'words "a b  c"', '[1, 2, undefined]',
  'maxBound + 1 :: Int', '(9223372036854775807 :: Integer) + 1', 'foldr (\\x acc -> x : take 2 acc) [] [1..]',
  'zip [1..] "abc"', 'show (Just (-1.5))', 'read "[(1,True)]" :: [(Int,Bool)]', 'map (`div` 0) [1]',
  'let xs = 1 : map (*2) xs in xs !! 70', 'length (filter even [1..3000])', 'sort [3,1,2]',
  'fromIntegral (3 :: Int) / 2', 'mapM_ print [1,2]', 'error "boom"', 'concatMap show [1..30]'
].freeze

def native_run(native)
  Rhci::VM::Machine.native = native
  out = RT::FakeIO.new
  s = Rhci::Session.new(stdout: out)
  results = NATIVE_INPUTS.map do |i|
    before = s.steps
    r = s.eval(i)
    [i, r.status, r.message, s.steps - before]
  end
  [out.written, results]
ensure
  Rhci::VM::Machine.native = true
end

RT.suite 'native machine' do
  RT.test 'the C loop agrees with the Ruby loop' do
    next unless Rhci::VM::Machine::NATIVE

    ruby_out, ruby_res = native_run(false)
    c_out, c_res = native_run(true)
    RT.eq ruby_out, c_out
    ruby_res.each_with_index { |r, i| RT.eq r, c_res[i] }
  end
end
