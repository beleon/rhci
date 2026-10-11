# frozen_string_literal: true

# Equivalent spellings of a module's source (test/fuzz/progs.rb --relayout):
# lines broken at a space into an indented continuation, `{- -}` comments
# (some nested) between tokens, `--` comments and blank lines, tabs in the
# indentation, and the top level in explicit braces with semicolons. GHC
# gets the same text, so a spelling that turns out invalid still has to be
# rejected the same way; the transformations aim to keep programs valid.
module Fuzz
  class Relayout
    LAYOUT_WORDS = %w[where let do of].freeze

    def initialize(r)
      @r = r
    end

    def chance(p)
      @r.rand < p
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def apply(src)
      lines = src.split("\n", -1)
      lines = lines.map { |l| chance(0.2) ? block_comment(l) : l }
      lines = lines.flat_map { |l| chance(0.25) ? break_line(l) : [l] }
      lines = lines.flat_map { |l| comment_lines(l) }
      lines = lines.map { |l| chance(0.5) ? tabs(l) : l }
      lines = braces(lines) if chance(0.25)
      lines.join("\n")
    end

    # Offsets of the spaces in l that are outside string and Char literals
    # and before any `--` comment.
    def code_spaces(l)
      out = []
      i = 0
      while i < l.length
        c = l[i]
        if c == '"'
          i += 1
          i += (l[i] == '\\' ? 2 : 1) while i < l.length && l[i] != '"'
        elsif c == "'" && (i.zero? || !word_char?(l[i - 1]))
          j = l[i + 1] == '\\' ? l.index("'", i + 2) : i + 2
          i = j if j && l[j] == "'"
        elsif c == '-' && l[i + 1] == '-' && (i.zero? || !'!#$%&*+./<=>?@\\^|~:'.include?(l[i - 1]))
          break
        elsif c == ' '
          out << i
        end
        i += 1
      end
      out
    end

    def word_char?(c)
      c =~ /[A-Za-z0-9_']/
    end

    def indent(l)
      l.length - l.lstrip.length
    end

    # A continuation line, indented to where the break is (deeper than any
    # layout block the line opened before it); only where the rest of the
    # line opens no block of its own.
    def break_line(l)
      first = indent(l)
      spaces = code_spaces(l).select { |i| i > first && l[i + 1] && l[i + 1] != ' ' }
      spaces.select! do |i|
        rest = l[(i + 1)..-1]
        before = l[0, i].split(' ').last
        !LAYOUT_WORDS.include?(before) && rest.split(/[^A-Za-z0-9_']+/).none? { |w| LAYOUT_WORDS.include?(w) }
      end
      return [l] if spaces.empty?

      i = pick(spaces)
      [l[0, i], (' ' * (i + 1)) + l[(i + 1)..-1]]
    end

    # Only on a line that opens no layout block: a comment moves the tokens
    # after it, and with them the column of a block whose items go on below.
    def block_comment(l)
      return l if l.split(/[^A-Za-z0-9_']+/).any? { |w| LAYOUT_WORDS.include?(w) }

      spaces = code_spaces(l).select { |i| i > indent(l) }
      return l if spaces.empty?

      i = pick(spaces)
      l[0, i] + pick([' {- c -} ', ' {-{- nested -}-} ', '{--}', ' {- -- not a line comment -} ']) + l[i..-1]
    end

    def comment_lines(l)
      out = [l]
      out = [l + pick(['  -- note', ' --', ' -- | doc'])] if chance(0.1) && !l.strip.empty? && !l.include?('--')
      out.unshift(' ' * @r.rand(0..12) + pick(['-- comment', '', '{- block -}'])) if chance(0.08)
      out
    end

    # Leading spaces as tabs (GHC's tab stops are every 8 columns).
    def tabs(l)
      n = indent(l)
      return l if n < 8 || l[0, n].include?("\t")

      ("\t" * (n / 8)) + (' ' * (n % 8)) + l[n..-1]
    end

    # `module M where { decl ; decl ; ... }`: the top level without layout.
    def braces(lines)
      head = lines.index { |l| l.start_with?('module ') && l.rstrip.end_with?(' where') }
      return lines if head.nil?

      out = lines[0..head]
      out[head] += ' {'
      first = true
      lines[(head + 1)..-1].each do |l|
        top = !l.empty? && l[0] != ' ' && l[0] != "\t" && !l.start_with?('--', '{-')
        if top && !first
          out << "; #{l}"
        else
          out << l
        end
        first = false if top
      end
      out << '}'
    end
  end
end
