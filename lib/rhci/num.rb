# frozen_string_literal: true

module Rhci
  # Exact numeric primitives shared by both runtimes. Never relies on Ruby's
  # own Float printing/parsing or Float#to_i beyond 2^53 (wrong on mruby,
  # see CLAUDE.md); everything goes through Math.frexp/ldexp and Integers.
  module Num
    INT_MIN = -(2**63)
    INT_MAX = 2**63 - 1
    TWO64 = 2**64
    TWO63 = 2**63
    MANT_BITS = 53
    MIN_EXP = -1074 # exponent of the smallest subnormal
    HIDDEN = 2**52

    # ---- Int (64-bit, wrapping) ---------------------------------------------

    def self.wrap_int(x)
      return x if x >= INT_MIN && x <= INT_MAX

      ((x + TWO63) % TWO64) - TWO63
    end

    # Truncating division and remainder (Haskell quot/rem); b != 0.
    def self.quot(a, b)
      q = a / b
      q += 1 if q < 0 && q * b != a
      q
    end

    def self.rem(a, b)
      a - b * quot(a, b)
    end

    # ---- Double structure ------------------------------------------------------

    def self.negative_zero?(x)
      x.zero? && (1.0 / x) < 0
    end

    # mruby's Float#== says NaN == NaN (an identity shortcut), so NaN is
    # detected with Float#nan? and equality goes through double_eq.
    def self.nan?(x)
      x.nan?
    end

    def self.infinite?(x)
      !x.nan? && (x - x).nan? # inf - inf is NaN
    end

    # IEEE negation. mruby's unary minus on a Float is 0 - x, which turns
    # -0.0 into 0.0; multiplying by -1.0 is exact and keeps the sign.
    def self.negate_double(x)
      x * -1.0
    end

    # IEEE equality: NaN equals nothing, -0.0 equals 0.0.
    def self.double_eq(a, b)
      !a.nan? && !b.nan? && a == b
    end

    # GHC's decodeFloat for finite x: [mantissa, exponent] with
    # x == mantissa * 2**exponent and |mantissa| in [2^52, 2^53) (0 -> [0, 0]).
    def self.decode_double(x)
      return [0, 0] if x.zero?
      return [x < 0 ? -HIDDEN : HIDDEN, 972] if infinite?(x) # GHC's decodeFloat of ±Infinity
      # GHC's answer for NaN depends on its sign bit, which Ruby cannot see.
      raise UnsupportedError, 'decodeFloat of NaN is not supported' if nan?(x)

      fr, ex = Math.frexp(x.abs)
      m = Math.ldexp(fr, MANT_BITS).to_i # < 2^53: exact on both runtimes
      [x < 0 ? -m : m, ex - MANT_BITS]
    end

    # The IEEE bit pattern as an Integer (tests and diagnostics).
    def self.double_to_bits(x)
      return 0x7FF8000000000000 if nan?(x)

      sign = x < 0 || negative_zero?(x) ? TWO63 : 0
      a = x.abs
      return sign | 0x7FF0000000000000 if infinite?(a)
      return sign if a.zero?

      m, e = decode_double(a)
      if e < MIN_EXP # subnormal: biased exponent 0, no hidden bit
        sign | (m >> (MIN_EXP - e))
      else
        sign | ((e + 1075) << 52) | (m - HIDDEN)
      end
    end

    def self.bits_to_double(bits)
      sign = bits >= TWO63 ? -1.0 : 1.0
      biased = (bits >> 52) & 0x7FF
      frac = bits & (HIDDEN - 1)
      if biased == 0x7FF
        return frac.zero? ? sign * (1.0 / 0.0) : 0.0 / 0.0
      end

      mag = biased.zero? ? Math.ldexp(frac.to_f, MIN_EXP) : Math.ldexp((frac + HIDDEN).to_f, biased - 1075)
      sign * mag
    end

    # C pow semantics (what GHC's ** uses): a negative base with a
    # non-integral exponent is NaN, never a Complex as in CRuby.
    def self.pow(a, b)
      return 0.0 / 0.0 if a < 0 && !nan?(b) && !infinite?(b) && b % 1.0 != 0.0

      a**b
    end

    # ---- conversions ------------------------------------------------------------

    # Correctly rounded (to nearest, ties to even) Integer -> Double.
    def self.integer_to_double(n)
      return 0.0 if n.zero?

      a = n.abs
      bl = a.bit_length
      if bl <= MANT_BITS
        d = a.to_f
      else
        shift = bl - MANT_BITS
        m = a >> shift
        r = a - (m << shift)
        half = 1 << (shift - 1)
        m += 1 if r > half || (r == half && m.odd?)
        d = Math.ldexp(m.to_f, shift)
      end
      n < 0 ? -d : d
    end

    # Correctly rounded n/d -> Double (d > 0), subnormals and overflow
    # included. This is how fractional literals become Doubles.
    def self.rational_to_double(n, d)
      return 0.0 if n.zero?

      neg = n < 0
      n = n.abs
      e = n.bit_length - d.bit_length - MANT_BITS
      loop do
        q = scaled_quotient(n, d, e)
        if q >= 2 * HIDDEN then e += 1
        elsif q < HIDDEN then e -= 1
        else break
        end
      end
      e = MIN_EXP if e < MIN_EXP
      num, den = e >= 0 ? [n, d << e] : [n << -e, d]
      q, r = num.divmod(den)
      q += 1 if 2 * r > den || (2 * r == den && q.odd?)
      x = Math.ldexp(q.to_f, e)
      neg ? -x : x
    end

    def self.scaled_quotient(n, d, e)
      e >= 0 ? n / (d << e) : (n << -e) / d
    end

    # A literal mantissa * 10**exp10 (exact, from the lexer) -> Double.
    def self.literal_to_double(mantissa, exp10)
      return 0.0 if mantissa.zero?

      digits = mantissa.to_s.length
      return 1.0 / 0.0 if digits + exp10 > 310
      return 0.0 if digits + exp10 < -330

      if exp10 >= 0
        rational_to_double(mantissa * 10**exp10, 1)
      else
        rational_to_double(mantissa, 10**-exp10)
      end
    end

    # Exact truncation toward zero of a finite Double.
    def self.truncate_double(x)
      m, e = decode_double(x)
      return m << e if e >= 0

      m < 0 ? -((-m) >> -e) : m >> -e
    end

    # Whether a finite Double is an integer.
    def self.integral_double?(x)
      m, e = decode_double(x)
      e >= 0 || (m.abs & ((1 << -e) - 1)).zero?
    end

    def self.floor_double(x)
      t = truncate_double(x)
      x < 0 && !integral_double?(x) ? t - 1 : t
    end

    def self.ceiling_double(x)
      t = truncate_double(x)
      x > 0 && !integral_double?(x) ? t + 1 : t
    end

    # Round half to even (Haskell's `round`).
    def self.round_double(x)
      m, e = decode_double(x)
      return m << e if e >= 0

      shift = -e
      a = m.abs
      q = a >> shift
      r = a - (q << shift)
      half = 1 << (shift - 1)
      q += 1 if r > half || (r == half && q.odd?)
      m < 0 ? -q : q
    end

    # ---- show for Double (GHC.Float, ported) --------------------------------------

    def self.show_double(x)
      return 'NaN' if nan?(x)
      return x < 0 ? '-Infinity' : 'Infinity' if infinite?(x)

      neg = x < 0 || negative_zero?(x)
      ds, e = float_to_digits(x.abs)
      s = if e < 0 || e > 7
            exponent_form(ds, e)
          else
            fixed_form(ds, e)
          end
      neg ? "-#{s}" : s
    end

    def self.exponent_form(ds, e)
      return '0.0e0' if ds == [0]
      return "#{ds[0]}.0e#{e - 1}" if ds.length == 1

      "#{ds[0]}.#{ds[1..-1].join}e#{e - 1}"
    end

    def self.fixed_form(ds, e)
      return "0.#{'0' * -e}#{ds.join}" if e <= 0

      int_part = ds[0, e].join
      int_part += '0' * (e - ds.length) if ds.length < e
      frac = ds.length > e ? ds[e..-1].join : ''
      "#{int_part.empty? ? '0' : int_part}.#{frac.empty? ? '0' : frac}"
    end

    # Burger & Dybvig free-format digit generation exactly as GHC.Float's
    # floatToDigits (base 10, Double), including its non-inclusive
    # termination tests and its k estimate. x >= 0, finite.
    def self.float_to_digits(x)
      return [[0], 0] if x.zero?

      p = MANT_BITS
      f0, e0 = decode_double(x)
      n = MIN_EXP - e0
      f, e = n > 0 ? [f0 >> n, e0 + n] : [f0, e0]
      top = 1 << (p - 1)
      if e >= 0
        be = 1 << e
        r, s, m_up, m_dn = f == top ? [f * be * 4, 4, be * 2, be] : [f * be * 2, 2, be, be]
      elsif e > MIN_EXP && f == top
        r, s, m_up, m_dn = [f * 4, (1 << (-e + 1)) * 2, 2, 1]
      else
        r, s, m_up, m_dn = [f * 2, (1 << -e) * 2, 1, 1]
      end

      lx = p - 1 + e0
      k1 = quot(lx * 8651, 28738)
      k = lx >= 0 ? k1 + 1 : k1
      loop do
        ok = k >= 0 ? r + m_up <= 10**k * s : 10**-k * (r + m_up) <= s
        break if ok

        k += 1
      end

      if k >= 0
        rn = r
        sn = s * 10**k
        up = m_up
        dn_ = m_dn
      else
        bk = 10**-k
        rn = r * bk
        sn = s
        up = m_up * bk
        dn_ = m_dn * bk
      end
      digits = []
      loop do
        d, rn = (rn * 10).divmod(sn)
        up *= 10
        dn_ *= 10
        low = rn < dn_
        high = rn + up > sn
        if low && !high
          digits << d
          break
        elsif high && !low
          digits << d + 1
          break
        elsif low && high
          digits << (rn * 2 < sn ? d : d + 1)
          break
        end
        digits << d
      end
      [digits, k]
    end
  end
end
