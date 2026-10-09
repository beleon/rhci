# frozen_string_literal: true

module Rhci
  # GHC's Unicode character properties, from the tables in unicode_data.rb
  # (generated from GHC itself). Each table is decoded on first use, so
  # startup pays nothing.
  module Unicode
    # The general category of code point c, as GHC's fromEnum of
    # GeneralCategory (0 UppercaseLetter .. 29 NotAssigned).
    def self.category(c)
      starts = @cat_starts || decode_categories
      lo = 0
      hi = starts.length - 1
      while lo < hi
        mid = (lo + hi + 1) / 2
        if starts[mid] <= c
          lo = mid
        else
          hi = mid - 1
        end
      end
      @cat_values[lo]
    end

    def self.to_upper(c)
      c + ((@upper ||= decode_map(UPPER_MAP))[c] || 0)
    end

    def self.to_lower(c)
      c + ((@lower ||= decode_map(LOWER_MAP))[c] || 0)
    end

    def self.to_title(c)
      c + ((@title ||= decode_map(TITLE_MAP))[c] || 0)
    end

    # The derived property Uppercase (GHC's isUpperCase).
    def self.uppercase?(c)
      in_ranges?(@uppercase ||= decode_numbers(UPPERCASE_RANGES), c)
    end

    # The derived property Lowercase (GHC's isLowerCase).
    def self.lowercase?(c)
      in_ranges?(@lowercase ||= decode_numbers(LOWERCASE_RANGES), c)
    end

    def self.decode_categories
      text = CATEGORY_RUNS.join
      starts = []
      values = []
      at = 0
      i = 0
      n = text.length
      while i < n
        values << (text.getbyte(i) - 65)
        starts << at
        i += 1
        len = 0
        while i < n
          b = text.getbyte(i)
          break if b >= 65 && b <= 95

          len = (len * 36) + (b <= 57 ? b - 48 : b - 87)
          i += 1
        end
        at += len
      end
      @cat_values = values
      @cat_starts = starts
    end

    # Base-36 numbers separated by commas, possibly negative.
    def self.decode_numbers(parts)
      text = parts.join
      out = []
      i = 0
      n = text.length
      while i < n
        neg = text.getbyte(i) == 45
        i += 1 if neg
        v = 0
        while i < n
          b = text.getbyte(i)
          break if b == 44

          v = (v * 36) + (b <= 57 ? b - 48 : b - 87)
          i += 1
        end
        i += 1
        out << (neg ? -v : v)
      end
      out
    end

    # Runs of (start, count, step, delta) into a Hash code point => delta.
    def self.decode_map(parts)
      nums = decode_numbers(parts)
      map = {}
      i = 0
      while i < nums.length
        cp = nums[i]
        k = 0
        while k < nums[i + 1]
          map[cp] = nums[i + 3]
          cp += nums[i + 2]
          k += 1
        end
        i += 4
      end
      map
    end

    # ranges: a flat sorted list of inclusive (start, end) pairs.
    def self.in_ranges?(ranges, c)
      lo = 0
      hi = (ranges.length / 2) - 1
      while lo <= hi
        mid = (lo + hi) / 2
        if c < ranges[2 * mid]
          hi = mid - 1
        elsif c > ranges[(2 * mid) + 1]
          lo = mid + 1
        else
          return true
        end
      end
      false
    end
  end
end
