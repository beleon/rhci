# frozen_string_literal: true

def lex(src)
  Rhci::Lexer.tokenize(src).map { |t| [t.kind, t.text] }[0..-2]
end

def lex_values(src)
  Rhci::Lexer.tokenize(src)[0..-2].map(&:value)
end

def lex_error(src)
  Rhci::Lexer.tokenize(src)
  nil
rescue Rhci::Error => e
  [e.kind, e.message]
end

RT.suite 'lexer' do
  RT.test 'identifiers, keywords, qualified names' do
    RT.eq [[:varid, 'x'], [:varid, "x'"], [:varid, '_y'], [:keyword, '_'], [:conid, 'Just']], lex("x x' _y _ Just")
    RT.eq [[:keyword, 'let'], [:keyword, 'in'], [:keyword, 'where']], lex('let in where')
    RT.eq [[:qvarid, 'Data.List.sort'], [:qconid, 'M.Just'], [:qvarsym, 'M.+']], lex('Data.List.sort M.Just M.+')
    t = Rhci::Lexer.tokenize('Data.Map.lookup')[0]
    RT.eq ['Data.Map', 'lookup'], [t.qual, t.name]
  end

  RT.test 'composition without spaces is a qualified name, as in Haskell' do
    RT.eq [[:qvarid, 'Just.f']], lex('Just.f')
    RT.eq [[:conid, 'Just'], [:varsym, '.'], [:varid, 'f']], lex('Just . f')
  end

  RT.test 'operators and reserved operators' do
    RT.eq [[:varsym, '+'], [:varsym, '>>='], [:consym, ':'], [:consym, ':+:'], [:reservedop, '->'],
           [:reservedop, '::'], [:reservedop, '..'], [:reservedop, '\\'], [:varsym, '-->']],
          lex('+ >>= : :+: -> :: .. \\ -->')
  end

  RT.test 'comments, including nested ones and dash-operators' do
    RT.eq [[:integer, '1']], lex('1 -- comment')
    RT.eq [[:integer, '1'], [:integer, '2']], lex("1 {- a {- nested -} b -} 2")
    RT.eq [[:integer, '1'], [:varsym, '--|'], [:integer, '2']], lex('1 --| 2')
    RT.eq [[:integer, '1']], lex('1 ---')
    RT.eq [:parse, "<interactive>:1:3: unterminated `{-'"], lex_error('1 {- x')
  end

  RT.test 'numeric literals are exact' do
    RT.eq [42, 255, 8, 5, 1_000_000], lex_values('42 0xff 0o10 0b101 1_000_000')
    RT.eq [[15, -1], [1, 7], [50, -325], [12345678, -2]], lex_values('1.5 1e7 5.0e-324 1234_56.78')
    RT.eq [[:integer, '1'], [:reservedop, '..'], [:integer, '5']], lex('1..5')
    RT.eq '18446744073709551616', lex_values('18446744073709551616')[0].to_s
  end

  RT.test 'hexadecimal float literals are refused, not misread' do
    RT.eq :unsupported, lex_error('0x1.8p1')[0]
  end

  RT.test 'character literals and escapes' do
    RT.eq [97, 10, 39, 92, 955, 1, 127, 7, 65, 65, 65], lex_values("'a' '\\n' '\\'' '\\\\' 'λ' '\\SOH' '\\DEL' '\\a' '\\65' '\\x41' '\\o101'")
    RT.eq [0, 27, 31], lex_values("'\\^@' '\\^[' '\\^_'")
    RT.eq :parse, lex_error("'ab'")[0]
    RT.eq :parse, lex_error("'\\&'")[0]
  end

  RT.test 'string literals: \\& is empty, SOH beats SO, gaps vanish' do
    RT.eq [[1234, 53]], lex_values('"\\1234\\&5"')
    RT.eq [[1]], lex_values('"\\SOH"')
    RT.eq [[14, 72]], lex_values('"\\SO\\&H"')
    RT.eq [[97, 98]], lex_values("\"a\\\n   \\b\"")
    RT.eq [[99, 97, 102, 233]], lex_values('"café"')
  end

  RT.test 'bad escapes and out-of-range characters' do
    RT.eq :parse, lex_error('"\\q"')[0]
    RT.eq :parse, lex_error('"\\1114112"')[0]
    RT.eq :parse, lex_error("\"abc\ndef\"")[0]
  end

  RT.test 'non-ASCII outside literals is refused' do
    RT.eq :unsupported, lex_error('x ∘ y')[0]
  end

  RT.test 'LANGUAGE pragmas are refused; other pragmas are comments' do
    RT.eq :unsupported, lex_error('{-# LANGUAGE LambdaCase #-} 1')[0]
    RT.eq [[:integer, '1']], lex('{-# INLINE f #-} 1')
  end

  RT.test 'positions: columns use 8-column tab stops; bol marks line starts' do
    ts = Rhci::Lexer.tokenize("a\n\tb c")
    RT.eq [[1, 1, true], [2, 9, true], [2, 11, false]], ts[0..2].map { |t| [t.line, t.col, t.bol] }
  end

  RT.test 'whitespace-sensitive ! and @' do
    RT.eq [[:varid, 'f'], [:bang, '!'], [:varid, 'x']], lex('f !x')
    RT.eq [[:varid, 'a'], [:varsym, '!'], [:varid, 'b']], lex('a ! b')
    RT.eq [:tight, :prefix], [Rhci::Lexer.tokenize('x@y')[1].value, Rhci::Lexer.tokenize('f @Int')[1].value]
  end
end
