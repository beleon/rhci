# frozen_string_literal: true

# Definitions whose types come from defaulting and the monomorphism
# restriction (test/fuzz/run.rb --defaulting). Each case is one group of
# unannotated (sometimes annotated) numeric definitions, loaded from a file
# (Haskell 2010 defaulting, the MR: a binding without arguments is
# monomorphic, and the whole module decides its type) and typed at the
# prompt (GHCi's extended defaulting, no MR), followed by the same inputs
# using the definitions: printing them, `:t`, and uses at other types.
# Only Prelude names, so the file needs no imports.
module Fuzz
  class DefaultGen
    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a.empty? ? nil : a[@r.rand(a.length)]
    end

    def chance(p)
      @r.rand < p
    end

    LITERALS = ['3', '2.5', '2 ^ 70', '7 `div` 2', 'fromIntegral (length "abc")', 'sum []', 'read "12"', '10 / 4',
                'toEnum 65', "fromEnum 'a'", 'round 2.5', 'truncate 1e10', 'floor (-0.5)', 'length []', '2 ^ 64',
                'realToFrac 1.5', 'maxBound', '0x10', '1e3', 'pi', 'product [1 .. 25]'].freeze

    # x: an earlier numeric value, y: another, f: an earlier function.
    DERIVED = ['x + y', 'x * 2', 'x / 2', 'x `div` 2', 'fromIntegral x', 'truncate x', 'round (x * 1.5)', 'sqrt x',
               'x + length "ab"', 'max x 3', 'negate x', 'x ^ 2', '2 ^ (x `mod` 70)', 'x - 2 ^ 63', 'f x', 'f 2.5', 'f 3',
               'toInteger x', 'realToFrac x', 'x `mod` 7', 'fromIntegral x / 3', 'x ** 0.5', 'minimum [x, y]',
               'x + 0.5', 'fromIntegral (x `div` 2) + y', 'succ x', 'abs x - 10', 'x * maxBound'].freeze

    OTHERS = ['show x', '[x, y]', '(x, y)', '[x .. x + 2]', 'show (x / 2)', 'x == y', 'even x', 'replicate 2 x',
              'show []', 'show Nothing', 'reverse []', 'mempty', 'minBound', '[]', 'show (read "5")', 'x < 2.5',
              'compare x y', 'Just x', 'show (f x)'].freeze

    FUNCTIONS = ['%s z = z + x', '%s = (+ x)', '%s = \\z -> z * 2', '%s z = z / 2', '%s z = fromIntegral z * x',
                 '%s = negate', '%s z = truncate (z * 2.5)', '%s = sum', '%s z = z `div` 2 + x', '%s = (^ 2)',
                 '%s z = (z, x)', '%s = show'].freeze

    SIGNATURES = %w[Int Integer Double].freeze

    # [definitions (each a line, a signature line before some), uses].
    def case_body
      nums = []
      funs = []
      defs = []
      names = %w[a b c d e].first(@r.rand(2..5))
      names.each do |n|
        x = pick(nums) || '1'
        y = pick(nums) || '2'
        f = pick(funs) || 'negate'
        if chance(0.25)
          fname = "f#{n}"
          defs << "#{fname} :: #{(t = pick(SIGNATURES))} -> #{t}" if chance(0.2)
          defs << format(pick(FUNCTIONS), fname).gsub(/\bx\b/, x)
          funs << fname
        end
        rhs = if nums.empty? || chance(0.3) then pick(LITERALS)
              elsif chance(0.2) then pick(OTHERS)
              else pick(DERIVED)
              end
        rhs = rhs.gsub(/\bx\b/, x).gsub(/\by\b/, y).gsub(/\bf\b/, f)
        defs << "#{n} :: #{pick(SIGNATURES)}" if chance(0.15)
        defs << "#{n} = #{rhs}"
        nums << n
      end
      [defs, uses(nums, funs), nums]
    end

    def uses(nums, funs)
      out = []
      (nums + funs).each do |n|
        out << ":t #{n}"
        out << n if nums.include?(n)
      end
      3.times do
        n = pick(nums)
        out << if !funs.empty? && chance(0.3)
                 "#{pick(funs)} #{pick(['2.5', '(3 :: Int)', '4', n])}"
               else
                 pick(['%s + 1', '%s / 2', '%s `div` 2', '(%s :: Int)', '(%s :: Double)', 'show %s', '[%s, 1.5]',
                       '%s + length []', 'fromIntegral %s * 0.5']) % n
               end
      end
      out
    end

    # Module name => [source, definitions, uses].
    def cases(count)
      (1..count).to_h do |i|
        defs, uses, nums = case_body
        name = "D#{i}"
        if chance(0.35)
          # The group local to one binding: a `where` has the monomorphism
          # restriction in a file too (and none at the prompt), and its
          # defaulting happens with the binding's.
          defs = ["wrapped = (#{nums.join(', ')})", '  where'] + defs.map { |d| "    #{d}" }
          uses = [':t wrapped', 'wrapped', 'fst (wrapped, ())']
        end
        [name, ["module #{name} where\n\n#{defs.join("\n")}\n", defs, uses]]
      end
    end
  end
end
