# frozen_string_literal: true

# Failing patterns in do blocks (test/fuzz/run.rb --fail): a refutable
# pattern that does not match calls the monad's fail -- Nothing in Maybe,
# [] in lists (and list comprehensions skip), a "user error (Pattern match
# failure in do expression at ...)" in IO, and a type error in a monad with
# no MonadFail instance (Either) -- while an irrefutable pattern (a tuple,
# `~p`, a variable) needs no MonadFail at all. Also explicit fail, ioError
# and userError, failures after output, and failing binds inside mapM and
# sequence.
module Fuzz
  class FailGen
    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def section(n)
      Fuzz::IMPORTS + Array.new(n) { probe }
    end

    def num
      pick(%w[0 1 2 3 7])
    end

    def maybe_val
      pick(['Nothing', "Just #{num}", "Just #{num}"])
    end

    def list_val
      pick(['[]', "[#{num}]", "[#{num}, #{num}]", "[#{num}, #{num}, #{num}]"])
    end

    def either_val
      pick(["Left #{num}", "Right #{num}"])
    end

    # A pattern and a scrutinee value of the same type, and a use of the
    # pattern's variables.
    def bind
      case @r.rand(9)
      when 0 then ['Just x', maybe_val, 'x']
      when 1 then ['(a:b:_)', list_val, 'a + b']
      when 2 then ['[x]', list_val, 'x']
      when 3 then ['Left e', either_val, 'e']
      when 4 then ['(x, y)', "(#{num}, #{num})", 'x + y']
      when 5 then ['~(Just x)', maybe_val, num]
      when 6 then ['x', num, 'x']
      when 7 then ['(Just x, y)', "(#{maybe_val}, #{num})", 'x * y']
      else ['Just (Just x)', pick(['Nothing', 'Just Nothing', "Just (Just #{num})"]), 'x']
      end
    end

    def probe
      p, v, use = bind
      p2, v2, use2 = bind
      case @r.rand(16)
      when 0, 1 then "do { #{p} <- Just (#{v}); return (#{use}) }"
      when 2 then "do { #{p} <- [#{v}, #{bind[1]}]; return (#{use}) }"
      when 3 then "[#{use} | #{p} <- [#{v}, #{v}]]"
      when 4, 5 then "do { #{p} <- return (#{v}); print (#{use}) }"
      when 6 then "do { print #{num}; #{p} <- return (#{v}); print (#{use}) }"
      when 7 then "do { #{p} <- return (#{v}); #{p2} <- return (#{v2}); print (#{use}, #{use2}) }"
      when 8 then "do { #{p} <- Right (#{v}); return (#{use}) } :: Either Int Int"
      when 9 then pick(['fail "boom" :: IO ()', '(fail "m" :: Maybe Int)', '(fail "l" :: [Int])',
                        'ioError (userError "oops")', "do { x <- return #{num}; fail (\"x=\" ++ show x) } :: IO ()",
                        "do { print #{num}; ioError (userError \"after\") }", '(fail "e" :: Either String Int)',
                        'userError "u"', 'show (userError "s")'])
      when 10 then "mapM (\\x -> do { Just y <- Just (if x > #{num} then Nothing else Just x); return y }) [1 .. #{num}]"
      when 11 then "sequence [do { #{p} <- Just (#{v}); return (#{use}) }, Just #{num}]"
      when 12 then "do { (#{p}) <- Just (#{v}); let { z = #{use} }; Just z }"
      when 13 then "[(#{use}, #{use2}) | #{p} <- [#{v}], #{p2} <- [#{v2}, #{v2}]]"
      when 14 then "do { #{p} <- mapM Just [#{v}]; return 1 }"
      else "concatMap (\\#{p} -> [#{use}]) [#{v}]"
      end
    end
  end
end
