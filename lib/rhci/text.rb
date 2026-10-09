# frozen_string_literal: true

module Rhci
  # String helpers that behave the same on both runtimes. mruby's
  # String#rstrip (and so #strip) leaves trailing whitespace in place when
  # the string contains non-ASCII characters (UTF-8 build); these work per
  # character.
  module Text
    SPACE = { ' ' => true, "\t" => true, "\n" => true, "\r" => true, "\v" => true, "\f" => true,
              "\0" => true }.freeze

    def self.rstrip(s)
      j = s.length
      j -= 1 while j > 0 && SPACE.key?(s[j - 1])
      s[0, j]
    end

    def self.lstrip(s)
      i = 0
      i += 1 while i < s.length && SPACE.key?(s[i])
      s[i..-1] || ''
    end

    def self.strip(s)
      lstrip(rstrip(s))
    end

    def self.blank?(s)
      lstrip(s).empty?
    end
  end
end
