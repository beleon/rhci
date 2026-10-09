# frozen_string_literal: true

# The machine, driven by hand-written Core (test/core_sexp.rb) until the
# desugarer exists.
VM_PRELUDE = <<~CORE
  (def undefined (let ((msg "Prelude.undefined")) (prim raise msg)))
  (def const (\\ (a b) a))
  (def plus (\\ (a b) (case a a1 (_ (case b b1 (_ (prim integerAdd a1 b1)))))))
  (def gtI (\\ (a b) (case a a1 (_ (case b b1 (_ (prim integerGt a1 b1)))))))
  (def fst (\\ (p) (case p _ ((Tup2 x y) x))))
  (def tail (\\ (xs) (case xs _ ((Cons h t) t))))
  (def enumFromTo (\\ (a b) (case a a1 (_ (case b b1 (_ (case (prim integerGt a1 b1) c
      ((True) (con Nil))
      ((False) (con Cons a1 (enumFromTo (prim integerAdd a1 1) b1))))))))))
  (def foldr (\\ (f z xs) (case xs _ ((Nil) z) ((Cons h t) (f h (foldr f z t))))))
  (def foldl' (\\ (f z xs) (case xs _ ((Nil) z) ((Cons h t) (case (f z h) z2 (_ (foldl' f z2 t)))))))
  (def length (\\ (xs) (foldl' (\\ (n x) (plus n 1)) 0 xs)))
  (def take (\\ (n xs) (case n n1 ((lit 0) (con Nil))
      (_ (case xs _ ((Nil) (con Nil)) ((Cons h t) (con Cons h (take (prim integerSub n1 1) t))))))))
  (def index (\\ (xs n) (case xs _ ((Cons h t) (case n n1 ((lit 0) h) (_ (index t (prim integerSub n1 1))))))))
  (def zipWith (\\ (f as bs) (case as _ ((Nil) (con Nil))
      ((Cons a at) (case bs _ ((Nil) (con Nil)) ((Cons b bt) (con Cons (f a b) (zipWith f at bt))))))))
  (def append (\\ (xs ys) (case xs _ ((Nil) ys) ((Cons h t) (con Cons h (append t ys))))))
  (def showInteger (\\ (n) (case n n1 (_ (prim integerShow n1)))))
  (def showListGo (\\ (xs) (case xs _ ((Nil) "]")
      ((Cons h t) (append (showInteger h) (case t _ ((Nil) "]") (_ (con Cons 44 (showListGo t)))))))))
  (def showList (\\ (xs) (con Cons 91 (showListGo xs))))
  (def putStr (\\ (s w) (case s _ ((Nil) (con IORes (con Unit)))
      ((Cons c cs) (case c c1 (_ (case (prim putChar c1) u (_ (putStr cs w)))))))))
  (def count (\\ (n) (case n n1 ((lit 0) 0) (_ (plus 1 (count (prim integerSub n1 1)))))))
  (def ones (con Cons 1 ones))
  (def fibs (con Cons 0 (con Cons 1 (zipWith plus fibs (tail fibs)))))
  (def boom (plus 1 undefined))
  (def big (count 50000))
CORE

def vm_prog(out = nil, limits = nil)
  CoreSexp::Program.new(VM_PRELUDE, out, limits)
end

def vm_exception(prog, src)
  prog.eval(src)
  nil
rescue Rhci::VM::HsException => e
  prog.machine.exception_message(e)
end

RT.suite 'machine' do
  RT.test 'evaluation and application' do
    p = vm_prog
    RT.eq 5, p.eval('(plus 2 3)')
    RT.eq 5, p.eval('((const plus 0) 2 3)'), 'over-application'
    RT.eq 3, p.eval('((plus 1) 2)'), 'partial application'
    RT.eq 97, p.eval('(case "abc" _ ((Cons c cs) c))')
  end

  RT.test 'laziness: unused arguments and fields are never evaluated' do
    p = vm_prog
    RT.eq 1, p.eval('(const 1 undefined)')
    RT.eq 1, p.eval('(fst (con Tup2 1 undefined))')
    RT.eq 2, p.eval('(length (con Cons undefined (con Cons undefined (con Nil))))')
    RT.eq [1, 1, 1], p.machine.list_to_a(p.eval('(take 3 ones)'))
  end

  RT.test 'sharing: a let-bound thunk is evaluated once' do
    p = vm_prog
    s0 = p.machine.steps
    p.eval('(count 2000)')
    single = p.machine.steps - s0
    s0 = p.machine.steps
    RT.eq 4000, p.eval('(let ((s (count 2000))) (plus s s))')
    shared = p.machine.steps - s0
    RT.ok shared < single + 50, "shared #{shared} steps vs single #{single}"
  end

  RT.test 'sharing: self-referential fibs is linear' do
    p = vm_prog
    v = p.eval('(index fibs 1000)')
    RT.eq '43466557686937456435688527675040625802564660517371780402481729089536555417949051890403879840079255169' \
          '295922593080322634775209689623239873322471161642996440906533187938298969649928516003704476137795166849228875',
          v.to_s
    RT.ok p.machine.steps < 100_000, "#{p.machine.steps} steps"
  end

  RT.test 'deep evaluation uses the heap, not the host stack' do
    p = vm_prog
    RT.eq 5_000_050_000, p.eval('(foldr plus 0 (enumFromTo 1 100000))')
    RT.eq 100_000, p.eval('(count 100000)')
  end

  RT.test 'exceptions: message, and a failed thunk re-raises when forced again' do
    p = vm_prog
    RT.eq 'Prelude.undefined', vm_exception(p, 'undefined')
    RT.eq 'Prelude.undefined', vm_exception(p, 'boom')
    RT.eq :raised, p.globals['boom'].value.state
    RT.eq 'Prelude.undefined', vm_exception(p, 'boom')
    RT.eq 'divide by zero', vm_exception(p, '(prim integerQuot 1 0)')
  end

  RT.test 'a thunk that demands itself is <<loop>>' do
    RT.eq '<<loop>>', vm_exception(vm_prog, '(let ((x x)) x)')
  end

  RT.test 'output is incremental: the prefix appears before the exception' do
    out = RT::FakeIO.new
    p = vm_prog(out)
    msg = vm_exception(p, '(putStr (showList (con Cons 1 (con Cons 2 (con Cons undefined (con Nil))))) (con Unit))')
    p.machine.flush_output
    RT.eq ['[1,2,', 'Prelude.undefined'], [out.written, msg]
    out2 = RT::FakeIO.new
    p2 = vm_prog(out2)
    p2.eval('(putStr (showList (enumFromTo 1 5)) (con Unit))')
    p2.machine.flush_output
    RT.eq '[1,2,3,4,5]', out2.written
  end

  RT.test 'limits stop evaluation and leave thunks recomputable' do
    p = vm_prog(nil, { steps: 20_000 })
    err = RT.raises(Rhci::VM::LimitExceeded) { p.eval('big') }
    RT.ok err.message.include?('step limit'), err.message
    RT.eq :pending, p.globals['big'].value.state
    p2 = vm_prog
    p2.machine.interrupt!
    RT.raises(Rhci::VM::LimitExceeded) { p2.eval('big') }
    RT.eq 50_000, p2.eval('big'), 'after an interrupt the same thunk evaluates normally'
  end

  RT.test 'primitives: Int wraps, Doubles show as in GHC' do
    p = vm_prog
    RT.eq(-9223372036854775808, p.eval('(prim intAdd 9223372036854775807 1)'))
    RT.eq '1.0e-2', p.machine.string(p.eval('(prim doubleShow 0.01)'))
    RT.ok Rhci::Num.nan?(p.eval('(prim doubleSqrt -1.0)')), 'sqrt (-1) is NaN'
    RT.ok Rhci::Num.nan?(p.eval('(prim doublePow -8.0 0.5)')), '(-8) ** 0.5 is NaN'
    RT.eq 'Prelude.chr: bad argument: 1114112', vm_exception(p, '(prim chr 1114112)')
  end
end
