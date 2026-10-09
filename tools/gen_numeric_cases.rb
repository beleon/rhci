# frozen_string_literal: true

# Writes oracle/numeric/cases.txt: deterministic inputs for the numeric
# differential suite. CRuby-only tool (uses pack and Random).
ROOT = File.expand_path('..', __dir__)
rng = Random.new(20261009)

def bits(x) = [x].pack('G').unpack1('Q>')
def hex(b) = b.to_s(16)
def from_bits(b) = [b].pack('Q>').unpack1('G')

cases = []
doubles = []

# Edge values and formatting boundaries.
edge = [0.0, -0.0, 1.0, -1.0, 0.1, -0.1, 0.5, 2.0, 10.0, 0.05, 1e7, 9999999.0, 12345678.9, 1234567.0,
        1e21, 1e22, 1e23, 0.30000000000000004, 1.0000000000000002e-2, 100.0, 3.141592653589793]
edge.each { |x| doubles << bits(x) }
[0x1, 0xFFFFFFFFFFFFF, 0x10000000000000, 0x7FEFFFFFFFFFFFFF, 0x3FB999999999999A, 0x3FB9999999999999,
 0x416312CFFFFFFFFF, 0x4163880000000000, 0x7FF0000000000000, 0xFFF0000000000000].each { |b| doubles << b }
# Every 5th power of two, and every power of ten with its neighbours.
(-1074..1023).step(5) { |k| doubles << bits(Math.ldexp(1.0, k)) }
(-323..308).each do |k|
  b = bits("1e#{k}".to_f)
  doubles.concat([b - 1, b, b + 1])
end
# Uniform random bit patterns (finite) and random "human" decimals.
3000.times do
  b = rng.rand(2**64)
  b = rng.rand(2**63) if ((b >> 52) & 0x7FF) == 0x7FF
  doubles << b
end
3000.times do
  digits = rng.rand(1..17)
  m = rng.rand(10**digits)
  x = "#{rng.rand(2).zero? ? '' : '-'}#{m}e#{rng.rand(-30..30)}".to_f
  doubles << bits(x)
end
doubles.uniq.each { |b| cases << "show #{hex(b)}" }

finite = doubles.uniq.select { |b| ((b >> 52) & 0x7FF) != 0x7FF }
finite.each_slice(6) { |s| cases << "decode #{hex(s[0])}" }
halves = [0.5, 1.5, 2.5, -0.5, -1.5, -2.5, 3.5, 1e15 + 0.5, 4503599627370495.5, -4503599627370495.5, 1e20, -1e20, 1e300]
halves.each { |x| cases << "trunc #{hex(bits(x))}" }
finite.each_slice(8) { |s| cases << "trunc #{hex(s[0])}" }

# Integer -> Double: around 53-bit rounding boundaries, ties, overflow.
ints = [0, 1, -1, 2**53, 2**53 + 1, 2**53 + 2, 2**53 + 3, 2**54 + 2, 2**54 + 6, -(2**53 + 1),
        2**1024, 2**1024 - 2**970, 2**1024 - 2**971, 2**1023 * 3 / 2]
800.times do
  bl = rng.rand(1..90)
  n = rng.rand(2**bl)
  n = -n if rng.rand(2).zero?
  ints << n
end
200.times do
  shift = rng.rand(1..40)
  ints << ((rng.rand(2**52) | 2**52) << shift) + (1 << (shift - 1)) # exact ties
end
ints.each { |n| cases << "fromInteger #{n}" }

# Rational -> Double.
800.times do
  n = rng.rand(2**rng.rand(1..120))
  d = rng.rand(1..2**rng.rand(1..120))
  n = -n if rng.rand(2).zero?
  cases << "fromRational #{n} #{d}"
end
[[1, 10], [1, 3], [2, 3], [1, 2**1075], [3, 2**1076], [1, 2**1074], [2**1024, 1], [2**1024 - 2**970, 1]].each do |n, d|
  cases << "fromRational #{n} #{d}"
end

# Decimal literals (lexed by rhci, `read` by GHC).
lits = %w[0.1 5.0e-324 2.4703282292062328e-324 2.4703282292062327e-324 1.7976931348623157e308
          1.7976931348623158e308 1.7976931348623159e308 1e400 1e-400 2.2250738585072014e-308
          2.2250738585072011e-308 9007199254740993 0.30000000000000004 123456789012345678901234567890]
1000.times do
  digits = rng.rand(1..25)
  m = (1..digits).map { rng.rand(10) }.join.sub(/\A0+(?=\d)/, '')
  m = "#{m[0]}.#{m[1..]}" if m.length > 1 && rng.rand(2).zero?
  lits << "#{m}e#{rng.rand(-345..310)}"
end
lits.each { |s| cases << "read #{s}" }

# Int: wrapping arithmetic and division signs on edge values.
edges = [-(2**63), -(2**63) + 1, -(2**32), -7, -1, 0, 1, 2, 7, 2**32, 2**63 - 2, 2**63 - 1]
%w[+ - *].each { |op| edges.each { |a| edges.each { |b| cases << "int #{op} #{a} #{b}" } } }
%w[quot rem div mod].each do |op|
  edges.each do |a|
    edges.each do |b|
      next if b.zero? || (a == -(2**63) && b == -1)

      cases << "int #{op} #{a} #{b}"
    end
  end
end
edges.each { |a| cases << "int negate #{a} 0" << "int abs #{a} 0" }

File.write(File.join(ROOT, 'oracle', 'numeric', 'cases.txt'), cases.join("\n") + "\n")
puts "#{cases.length} cases"
