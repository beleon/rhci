# frozen_string_literal: true

def rp(src)
  Rhci::Frontend.parse_repl(src)[0].sexp
end

def rp_error(src)
  Rhci::Frontend.parse_repl(src)
  nil
rescue Rhci::Error => e
  e.kind
end

def ex(src)
  Rhci::Frontend.parse_expression(src).sexp
end

RT.suite 'parser' do
  RT.test 'REPL input classification' do
    RT.eq '(repl-expr 1)', rp('1')
    RT.eq '(repl-let (fun x () (rhs 5)))', rp('let x = 5')
    RT.eq '(repl-expr (let ((fun x () (rhs 5))) x))', rp('let x = 5 in x')
    RT.eq '(repl-bind x getLine)', rp('x <- getLine')
    RT.eq '(repl-decls (fun x () (rhs 5)))', rp('x = 5')
    RT.eq '(repl-expr (:: x Int))', rp('x :: Int')
    RT.eq '(repl-decls (sig (x) Int) (fun x () (rhs 1)))', rp('x :: Int; x = 1')
    RT.eq '(repl-import (import Data.Maybe))', rp('import Data.Maybe')
    RT.eq '(repl-empty)', rp('   ')
    RT.eq '(repl-let)', rp('let')
    RT.eq :parse, rp_error('x = 1; 2')
  end

  RT.test 'function and pattern bindings' do
    RT.eq '(repl-decls (fun f ((pcon Just x) _) (rhs x)))', rp('f (Just x) _ = x')
    RT.eq '(repl-decls (fun (<+>) (a b) (rhs (op (+) a b))))', rp('a <+> b = a + b')
    RT.eq '(repl-decls (fun (.:) (f g x) (rhs x)))', rp('(f .: g) x = x')
    RT.eq '(repl-decls (fun f ((pcon (:) x xs)) (rhs x)))', rp('f (x:xs) = x')
    RT.eq '(repl-decls (patbind (ptuple a b) (rhs (tuple 1 2))))', rp('(a, b) = (1, 2)')
    RT.eq '(repl-decls (patbind (pcon (:) x xs) (rhs (list 1 2))))', rp('x : xs = [1, 2]')
    RT.eq '(repl-decls (fun f (-1) (rhs 0)))', rp('f (-1) = 0')
    RT.eq '(repl-decls (fun f ((as all (pcon (:) x _))) (rhs all)))', rp('f all@(x:_) = all')
    RT.eq :parse, rp_error('f x + g y = 1')
  end

  RT.test 'guards and where' do
    RT.eq '(repl-decls (fun sign (n) (grhs (| ((op (>) n 0)) 1) (| (otherwise) (neg 1)))))',
          rp('sign n | n > 0 = 1 | otherwise = -1')
    RT.eq '(repl-decls (fun h (n) (rhs r (where (fun r () (rhs (op (*) n k))) (fun k () (rhs 10))))))',
          rp("h n = r\n  where r = n * k\n        k = 10")
    RT.eq '(repl-decls (fun f (m) (grhs (| ((<- (pcon Just x) m) (op (>) x 0)) x))))',
          rp('f m | Just x <- m, x > 0 = x')
  end

  RT.test 'layout: implicit blocks and the parse-error(t) rule' do
    RT.eq '(let ((fun x () (rhs 1)) (fun y () (rhs 2))) (op (+) x y))', ex("let x = 1\n    y = 2\nin x + y")
    RT.eq '(paren (case x (alt 1 (rhs 2))))', ex('(case x of 1 -> 2)')
    RT.eq '(comp y (<- x xs) (letstmt (fun y () (rhs x))) (app odd y))', ex('[y | x <- xs, let y = x, odd y]')
    RT.eq '(do (<- x getLine) (app putStrLn x))', ex("do\n  x <- getLine\n  putStrLn x")
    RT.eq '(do (<- x getLine) (app putStrLn x))', ex('do { x <- getLine; putStrLn x }')
    RT.eq '(do (if c (app return 1) (app return 2)))', ex("do\n  if c\n  then return 1\n  else return 2")
    RT.eq :parse, rp_error("f x = y\nwhere y = 1")
  end

  RT.test 'nested layout closes outer blocks on dedent' do
    src = "f x = case x of\n  1 -> a\n    where a = 2\n  _ -> 0\ng = 3"
    RT.eq '(repl-decls (fun f (x) (rhs (case x (alt 1 (rhs a (where (fun a () (rhs 2))))) ' \
          '(alt _ (rhs 0))))) (fun g () (rhs 3)))', rp(src)
  end

  RT.test 'parentheses, tuples, sections' do
    RT.eq '(app map (rsect (+) 1) xs)', ex('map (+ 1) xs')
    RT.eq '(app map (lsect 1 (+)) xs)', ex('map (1 +) xs')
    RT.eq '(app map (rsect div 2) xs)', ex('map (`div` 2) xs')
    RT.eq '(app (paren (neg 1)) 5)', ex('(- 1) 5')
    RT.eq '(app (-) 1 2)', ex('(-) 1 2')
    RT.eq '(app (,,) 1 2 3)', ex('(,,) 1 2 3')
    RT.eq '(tuple 1 "a" (con True))'.sub('(con True)', 'True'), ex('(1, "a", True)')
    RT.eq '()', ex('()')
    RT.eq '(app (:) 1 [])', ex('(:) 1 []')
    RT.eq :unsupported, RT.error_kind { Rhci::Frontend.parse_expression('(1,)') }
  end

  RT.test 'lists, ranges, comprehensions' do
    RT.eq '(list 1 2 3)', ex('[1, 2, 3]')
    RT.eq '(range 1 _ _)', ex('[1 ..]')
    RT.eq '(range 1 3 9)', ex('[1,3..9]')
    RT.eq '(range (con Red) _ _)'.sub('(con Red)', 'Red'), ex('[Red ..]')
    RT.eq '(comp (op (+) x y) (<- x (list 1 2)) (<- y (list 10 20)))', ex('[x + y | x <- [1, 2], y <- [10, 20]]')
  end

  RT.test 'records' do
    RT.eq '(reccon P (px 1) (py (neg 2)))', ex('P { px = 1, py = -2 }')
    RT.eq '(recupd (paren (app P 1 2)) (py 9))', ex('(P 1 2) { py = 9 }')
    RT.eq '(app f (recupd p (x 1)))', ex('f p { x = 1 }')
  end

  RT.test 'lambda, if, case with guards' do
    RT.eq '(lam ((ptuple a b)) (op (+) a b))', ex('\\(a, b) -> a + b')
    RT.eq '(case 5 (alt n (grhs (| ((app even n)) "even") (| ((app odd n)) "odd"))))',
          ex('case 5 of n | even n -> "even" | odd n -> "odd"')
    RT.eq '(op (+) 1 (if c 2 3))', ex('1 + if c then 2 else 3')
  end

  RT.test 'types and signatures' do
    RT.eq '(repl-decls (sig (f) (qual () ((Eq a) (Show a)) (-> a (-> [a] String)))) (fun f (x) (rhs x)))',
          rp('f :: (Eq a, Show a) => a -> [a] -> String; f x = x')
    RT.eq '(:: x (Maybe (ttuple Int (-> a b))))', ex('x :: Maybe (Int, a -> b)')
    RT.eq '(:: x (qual (a) () (-> a a)))', ex('x :: forall a. a -> a')
  end

  RT.test 'data, newtype, class, instance, fixity' do
    RT.eq '(repl-decls (data T (a) (con Leaf) (con Node (T a) a (T a)) (deriving Show)))',
          rp('data T a = Leaf | Node (T a) a (T a) deriving Show')
    RT.eq '(repl-decls (data Op () (con (:+:) Int Int) (deriving Show Eq)))', rp('data Op = Int :+: Int deriving (Show, Eq)')
    RT.eq '(repl-decls (data S () (con S (! Int) Int) (deriving)))', rp('data S = S !Int Int')
    RT.eq '(repl-decls (newtype Age () (con Age Int) (deriving Show)))', rp('newtype Age = Age Int deriving Show')
    RT.eq '(repl-decls (class ((Eq a)) C a (sig (m) (-> a a))))', rp('class Eq a => C a where m :: a -> a')
    RT.eq '(repl-decls (instance () Show (T a) (fun show (_) (rhs "T"))))', rp('instance Show (T a) where show _ = "T"')
    RT.eq '(repl-decls (infixl 6 ((<+>))) (fun (<+>) (a b) (rhs a)))', rp('infixl 6 <+>; a <+> b = a')
  end

  RT.test 'unsupported extensions fail loudly' do
    RT.eq :unsupported, rp_error('f @Int 3')
    RT.eq :unsupported, rp_error('data T where')
    RT.eq :unsupported, RT.error_kind { Rhci::Frontend.parse_module("{-# LANGUAGE GADTs #-}\nx = 1", 'A.hs') }
  end

  RT.test 'bang patterns parse (GHC2021); semantics come with the desugarer' do
    RT.eq '(repl-decls (fun f ((bang x)) (rhs x)))', rp('f !x = x')
  end

  RT.test 'pattern-only syntax in expressions is a parse error' do
    RT.eq :parse, rp_error('x@y')
    RT.eq :parse, rp_error('f ~x')
  end

  RT.test 'modules' do
    m = Rhci::Frontend.parse_module("module Main (main) where\nimport Data.List\n\nmain = print 1\n", 'Main.hs')
    RT.eq '(module Main (import Data.List) (fun main () (rhs (app print 1))))', m.sexp
    RT.eq '(module Main (fun x () (rhs 1)) (fun y () (rhs 2)))', Rhci::Frontend.parse_module("x = 1\ny = 2\n", 'A.hs').sexp
  end

  RT.test 'deep nesting fails cleanly instead of overflowing the stack' do
    RT.eq :parse, rp_error('(' * 2000 + '1' + ')' * 2000)
  end

  RT.test 'long flat constructs do not recurse' do
    RT.eq 5000, Rhci::Frontend.parse_expression("[#{(1..5000).to_a.join(',')}]").elems.length
    chain = Rhci::Frontend.parse_expression((1..3000).to_a.join(' + '))
    RT.ok chain.is_a?(Rhci::AST::BinOp), 'a 3000-operand chain resolves'
  end
end
