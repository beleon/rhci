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

  RT.test 'String#rstrip on non-ASCII is broken on mruby; Rhci::Text is not' do
    RT.eq Rhci::Shim::MRUBY, "é \n".rstrip != 'é', 'documents the quirk' # lint:ok (the quirk itself)
    RT.eq 'λ é', Rhci::Text.strip("  λ é \t\n")
    RT.eq '', Rhci::Text.strip(" \n")
  end
end
