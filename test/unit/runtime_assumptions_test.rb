# frozen_string_literal: true

# Facts about the host Ruby that the design relies on (docs/ARCHITECTURE.md
# §4, CLAUDE.md "mruby facts"). If one of these starts failing, the runtime
# changed underneath us.
RT.suite 'runtime assumptions' do
  RT.test 'Integer is unbounded' do
    RT.eq '18446744073709551616', (2**64).to_s
    RT.eq '15511210043330985984000000', (1..25).inject(1) { |a, b| a * b }.to_s
  end

  RT.test 'Int wrapping formula' do
    wrap = ->(x) { ((x + 2**63) % 2**64) - 2**63 }
    RT.eq(-9223372036854775808, wrap.call(9223372036854775807 + 1))
    RT.eq 9223372036854775807, wrap.call(-9223372036854775808 - 1)
  end

  RT.test 'Integer / and % are Haskell div and mod; remainder is rem' do
    RT.eq [-4, 1], [-7 / 2, -7 % 2]
    RT.eq [-4, -1], [7 / -2, 7 % -2]
    RT.eq(-1, -7.remainder(2))
  end

  RT.test 'strings are code-point sequences' do
    RT.eq 4, 'café'.length
    RT.eq [97, 955], 'aλ'.codepoints
    RT.eq 'λ', ''.dup << 955
  end

  RT.test 'frexp/ldexp are exact, subnormals included' do
    RT.eq [0.8, -3], Math.frexp(0.1)
    tiny = Math.ldexp(1.0, -1074)
    RT.ok tiny > 0, 'ldexp(1, -1074) must be the smallest subnormal, not 0'
    RT.eq [0.5, -1073], Math.frexp(tiny)
  end

  RT.test 'Arrays and Strings are not length-capped (MRB_*_LENGTH_MAX=0)' do
    a = []
    i = 0
    while i < 1_000_000
      a << i
      i += 1
    end
    RT.eq 1_000_000, a.length
    RT.eq 2_000_000, ('ab' * 1_000_000).length
  end

  RT.test 'NaN: Float#nan? and ordered comparisons are reliable; == is not on mruby' do
    n = 0.0 / 0.0
    RT.ok n.nan?, 'nan?'
    RT.ok !(n < n) && !(n <= n) && !(n > 1.0), 'ordered comparisons with NaN are false'
    RT.ok !Rhci::Num.double_eq(n, n), 'double_eq(NaN, NaN) is false'
    RT.ok Rhci::Num.double_eq(0.0, -0.0), 'double_eq(0.0, -0.0) is true'
    RT.eq Rhci::Shim::MRUBY, n == n, 'mruby says NaN == NaN; CRuby does not' # documents the quirk
  end

  RT.test 'a bignum compared with a fixnum is compared whole (rhci-native fixes mruby 4.0.0)' do
    big = 2**64
    RT.ok !(big + 7 == 7) && !(big == 0) && !big.zero? && big != 0, 'bignum == fixnum'
    RT.ok !(7 == big + 7) && !(-big == 0), 'fixnum == bignum, negative bignum'
    RT.ok big == 2**64 && (big + 1) - 1 == big && big == 2.0**64, 'equal values still compare equal'
    RT.ok ![big].include?(0), 'Array#include? goes through =='
    min = -9_223_372_036_854_775_807 - 1
    RT.ok((-9_223_372_036_854_775_808 == min) && (min == -9_223_372_036_854_775_808), 'INT64_MIN as a bignum')
    big_min = -(2**63) # a bignum holding INT64_MIN on mruby
    RT.eq [0, 0, false, true, true, false], [big_min <=> min, min <=> big_min, big_min < min, big_min <= min,
                                             big_min >= min, min > big_min], 'ordering INT64_MIN as a bignum'
    RT.ok big_min < min + 1 && (min + 1) > big_min && (2**70 <=> 3) == 1 && (3 <=> 2**70) == -1, 'ordering'
    RT.ok 3 < 3.5 && (2**70) > 1.5 && !(3 < 0.0 / 0.0) && (3 <=> 0.0 / 0.0).nil?, 'with Floats and NaN'
  end

  RT.test 'bignum arithmetic with a fixnum operand (rhci-native fixes mruby 4.0.0)' do
    a = -18_446_744_073_709_551_614
    RT.eq [-18_446_744_073_709_551_623, -18_446_744_073_709_551_623, -18_446_744_073_709_551_623],
          [a + -9, -9 + a, a - 9], 'a carry into a new limb keeps the sign'
    RT.eq [-36_893_488_147_419_103_235, -9_223_372_036_854_775_809, 1_180_591_620_717_411_303_423],
          [~36_893_488_147_419_103_234, ~(2**63), ~(-(2**70))], '~'
    RT.eq [12, 12, -1_180_591_620_717_411_303_419], [-20_225_548_937_302_257_624_269_431_286_731_800_148 & 92,
                                                      92 & -20_225_548_937_302_257_624_269_431_286_731_800_148,
                                                      -(2**70) | 5], '& and | with a negative bignum'
    RT.eq [-147_573_952_589_676_412_929, -4_336_808_689_942_017_737, -1, -147_573_952_589_676_412_929],
          [(-(2**70) - 1) >> 3, -9_999_999_999_999_999_999_999_999_999_999_999_999 >> 61, -(2**70) >> 1000,
           (-(2**70) - 1) << -3], '>> of a negative bignum floors'
  end

  RT.test 'String#rstrip on non-ASCII is broken on mruby; Rhci::Text is not' do
    RT.eq Rhci::Shim::MRUBY, "é \n".rstrip != 'é', 'documents the quirk' # lint:ok (the quirk itself)
    RT.eq 'λ é', Rhci::Text.strip("  λ é \t\n")
    RT.eq '', Rhci::Text.strip(" \n")
  end

  RT.test 'the embedded Prelude source is byte-identical to prelude/Prelude.hs' do
    RT.eq File.read(File.join(RHCI_ROOT, 'prelude', 'Prelude.hs')), Rhci::PRELUDE_SOURCE
  end

  RT.test 'unary minus loses -0.0 on mruby; Num.negate_double does not' do
    z = 0.0
    RT.eq Rhci::Shim::MRUBY, (1.0 / -z) > 0, 'documents the quirk'
    RT.ok (1.0 / Rhci::Num.negate_double(z)) < 0, 'negate_double keeps the sign'
  end
end
