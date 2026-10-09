# frozen_string_literal: true

# Rhci::Unicode against GHC's own dump of its tables (oracle/unicode).
unicode_rows = File.read(File.join(RHCI_ROOT, 'oracle', 'unicode', 'tables.txt')).split("\n").map do |l|
  f = l.split(' ')
  [f[0], f[1..].map(&:to_i)]
end

RT.suite 'Unicode tables' do
  RT.test 'general category at both ends of every run' do
    cats = unicode_rows.select { |r| r[0] == 'C' }.map { |r| r[1] }
    bad = []
    cats.each_with_index do |(start, cat), i|
      stop = i + 1 < cats.length ? cats[i + 1][0] - 1 : 0x10FFFF
      bad << start if Rhci::Unicode.category(start) != cat || Rhci::Unicode.category(stop) != cat
    end
    RT.eq [], bad
  end

  RT.test 'case mappings, every mapped code point' do
    bad = []
    unicode_rows.each do |tag, (start, n, step, delta)|
      next unless tag == 'U' || tag == 'L' || tag == 'T'

      n.times do |k|
        c = start + (k * step)
        got = if tag == 'U' then Rhci::Unicode.to_upper(c)
              elsif tag == 'L' then Rhci::Unicode.to_lower(c)
              else Rhci::Unicode.to_title(c)
              end
        bad << [tag, c] unless got == c + delta
      end
    end
    RT.eq [], bad
    RT.eq [0x41, 0x41, 0x31], [Rhci::Unicode.to_upper(0x41), Rhci::Unicode.to_lower(0x41) - 32, Rhci::Unicode.to_title(0x31)]
  end

  RT.test 'Uppercase and Lowercase properties at range ends and just outside' do
    bad = []
    unicode_rows.each do |tag, (a, b)|
      next unless tag == 'P' || tag == 'Q'

      f = tag == 'P' ? ->(c) { Rhci::Unicode.uppercase?(c) } : ->(c) { Rhci::Unicode.lowercase?(c) }
      bad << [tag, a] unless f.call(a) && f.call(b) && !f.call(a - 1) && !f.call(b + 1)
    end
    RT.eq [], bad
  end
end
