# frozen_string_literal: true

# rhci's numeric primitives against ~14.5k results from real GHC
# (oracle/numeric: cases.txt -> Num.hs -> golden.txt). Exact string match.
num_dir = File.join(RHCI_ROOT, 'oracle', 'numeric')
num_cases = File.read(File.join(num_dir, 'cases.txt')).split("\n")
num_golden = File.read(File.join(num_dir, 'golden.txt')).split("\n")

def num_hex(x)
  Rhci::Num.double_to_bits(x).to_s(16)
end

def num_tuple(xs)
  "(#{xs.join(',')})"
end

def num_int_op(op, a, b)
  n = Rhci::Num
  case op
  when '+' then n.wrap_int(a + b)
  when '-' then n.wrap_int(a - b)
  when '*' then n.wrap_int(a * b)
  when 'quot' then n.wrap_int(n.quot(a, b))
  when 'rem' then n.rem(a, b)
  when 'div' then n.wrap_int(a / b)
  when 'mod' then a % b
  when 'negate' then n.wrap_int(-a)
  when 'abs' then n.wrap_int(a.abs)
  end
end

def num_literal(text)
  t = Rhci::Lexer.tokenize(text)[0]
  t.kind == :float ? Rhci::Num.literal_to_double(t.value[0], t.value[1]) : Rhci::Num.integer_to_double(t.value)
end

def num_case(words)
  n = Rhci::Num
  case words[0]
  when 'show' then n.show_double(n.bits_to_double(words[1].to_i(16)))
  when 'decode' then num_tuple(n.decode_double(n.bits_to_double(words[1].to_i(16))))
  when 'trunc'
    x = n.bits_to_double(words[1].to_i(16))
    num_tuple([n.truncate_double(x), n.floor_double(x), n.ceiling_double(x), n.round_double(x)])
  when 'fromInteger' then num_hex(n.integer_to_double(words[1].to_i))
  when 'fromRational' then num_hex(n.rational_to_double(words[1].to_i, words[2].to_i))
  when 'read' then num_hex(num_literal(words[1]))
  when 'int' then num_int_op(words[1], words[2].to_i, words[3].to_i).to_s
  end
end

RT.suite 'numerics vs GHC' do
  %w[show decode trunc fromInteger fromRational read int].each do |kind|
    RT.test kind do
      bad = []
      total = 0
      i = 0
      while i < num_cases.length
        words = num_cases[i].split(' ')
        if words[0] == kind
          total += 1
          got = begin
            num_case(words)
          rescue StandardError => e
            "#{e.class}: #{e.message}"
          end
          bad << "#{num_cases[i]}: GHC #{num_golden[i]}, rhci #{got}" if got != num_golden[i]
        end
        i += 1
      end
      RT.ok total > 0, "no #{kind} cases"
      RT.ok bad.empty?, "#{bad.length}/#{total} differ:\n      #{bad.first(8).join("\n      ")}"
    end
  end
end
