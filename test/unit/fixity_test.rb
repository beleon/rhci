# frozen_string_literal: true

def fx(src)
  Rhci::Frontend.parse_expression(src).sexp
end

def fx_error(src)
  Rhci::Frontend.parse_expression(src)
  nil
rescue Rhci::Error => e
  e.kind
end

RT.suite 'fixity' do
  RT.test 'precedence and associativity' do
    RT.eq '(op (+) 1 (op (*) 2 3))', fx('1 + 2 * 3')
    RT.eq '(op (-) (op (-) 1 2) 3)', fx('1 - 2 - 3')
    RT.eq '(op (^) 2 (op (^) 3 4))', fx('2 ^ 3 ^ 4')
    RT.eq '(op ($) f (op ($) g x))', fx('f $ g $ x')
    RT.eq '(op (:) 1 (op (:) 2 []))', fx('1 : 2 : []')
    RT.eq '(op (&&) (op (==) a b) (op (<) c d))', fx('a == b && c < d')
    RT.eq '(op div (op (+) 7 1) 2)'.sub('(op div (op (+) 7 1) 2)', '(op (+) 7 (op div 1 2))'), fx('7 + 1 `div` 2')
  end

  RT.test 'negation follows the Report' do
    RT.eq '(neg (op (^) 2 2))', fx('-2 ^ 2')
    RT.eq '(op (+) (neg 2) 3)', fx('- 2 + 3')
    RT.eq '(neg (op (*) a b))', fx('- a * b')
    RT.eq '(op (==) a (neg b))', fx('a == - b')
    RT.eq '(neg (op mod 5 3))', fx('-5 `mod` 3')
    RT.eq '(op (-) abs 7)', fx('abs -7')
    RT.eq :parse, fx_error('3 - -2')
    RT.eq :parse, fx_error('2 * -3')
    RT.eq :parse, fx_error('- - 2')
  end

  RT.test 'non-associative operators do not chain' do
    RT.eq :parse, fx_error('1 < 2 < 3')
    RT.eq :parse, fx_error('a == b == c')
  end

  RT.test 'sections must bind looser than their operand' do
    RT.eq '(rsect (+) (op (*) 1 2))', fx('(+ 1 * 2)')
    RT.eq :parse, fx_error('(* 1 + 2)')
    RT.eq :parse, fx_error('(a + b *)')
    RT.eq '(lsect (op (*) a b) (+))', fx('(a * b +)')
  end

  RT.test 'user fixity declarations, also later in the same group' do
    RT.eq '(let ((fun (<+>) (a b) (rhs a)) (infixr 2 ((<+>)))) (op (<+>) x (op (<+>) y z)))',
          fx('let a <+> b = a; infixr 2 <+> in x <+> y <+> z')
  end

  RT.test 'a local binding shadows an operator fixity (to infixl 9)' do
    RT.eq '(let ((fun (+) (a b) (rhs a))) (op (*) (op (+) 1 2) 3))', fx('let a + b = a in 1 + 2 * 3')
    RT.eq '(lam (div) (op (+) 1 (op div 7 2)))', fx('\\div -> 1 + 7 `div` 2')
    RT.eq '(lam (div) (op div (op (+) 1 7) 2))', fx('\\div -> 1 + 7 `div` 2').sub('(op (+) 1 (op div 7 2))', '(op div (op (+) 1 7) 2)')
  end

  RT.test 'patterns resolve too' do
    RT.eq '(case x (alt (pcon (:) a (pcon (:) b c)) (rhs a)))', fx('case x of a : b : c -> a')
    RT.eq '(case x (alt -1 (rhs 0)))', fx('case x of -1 -> 0')
    RT.eq :parse, fx_error('case x of - y -> 0')
  end

  RT.test 'fixity declaration without a binding is rejected' do
    RT.eq :compile, RT.error_kind { Rhci::Frontend.parse_repl('infixl 6 <+>') }
  end
end
