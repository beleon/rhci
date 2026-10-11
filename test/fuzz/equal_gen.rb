# frozen_string_literal: true

# Which of two equal values survives (test/fuzz/run.rb --equal): K's Eq and
# Ord look only at the number, so equal keys can carry different tags, and
# show reveals which one an operation kept -- Map insert/union/fromList/
# fromAscList/insertWith/alter, Set insert/union/fromList/fromAscList,
# max/min/maximum/maximumBy, sort/sortBy/sortOn stability, nub, union,
# group, insert, elem/lookup, Map keys after insertion.
module Fuzz
  class EqualGen
    DECLS = [':{', 'data K = K Int Char', 'instance Eq K where K a _ == K b _ = a == b',
             'instance Ord K where compare (K a _) (K b _) = compare a b', 'instance Show K where',
             "  showsPrec d (K a c) = showParen (d > 10) (showString \"K \" . showsPrec 11 a . showChar ' ' . showsPrec 11 c)",
             ':}'].freeze

    def initialize(seed)
      @r = Random.new(seed)
    end

    def pick(a)
      a[@r.rand(a.length)]
    end

    def section(n)
      Fuzz::IMPORTS + ['import Data.Ord'] + DECLS + Array.new(n) { probe }
    end

    def k
      "(K #{@r.rand(0..2)} '#{('a'.ord + @r.rand(0..5)).chr}')"
    end

    def ks(n = @r.rand(0..5))
      "[#{Array.new(n) { k }.join(', ')}]"
    end

    def kv
      "(#{k}, #{@r.rand(0..9)})"
    end

    def kvs
      "[#{Array.new(@r.rand(0..4)) { kv }.join(', ')}]"
    end

    TEMPLATES = [
      'M.insert K N (M.fromList KVS)', 'M.fromList KVS', 'M.union (M.fromList KVS) (M.fromList KVS)',
      'M.unionWith (+) (M.fromList KVS) (M.fromList KVS)', 'M.insertWith (+) K N (M.fromList KVS)',
      'M.fromListWith (+) KVS', 'M.keys (M.insert K N (M.fromList KVS))', 'M.fromAscList (sort KVS)',
      'M.fromDistinctAscList (M.toList (M.fromList KVS))', 'M.alter (fmap (+ 1)) K (M.fromList KVS)',
      'M.adjust (+ 1) K (M.fromList KVS)', 'M.lookupMin (M.fromList KVS)', 'M.lookupMax (M.fromList KVS)',
      'M.member K (M.fromList KVS)', 'M.intersection (M.fromList KVS) (M.fromList KVS)',
      'M.intersectionWith (,) (M.fromList KVS) (M.fromList KVS)', 'M.difference (M.fromList KVS) (M.fromList KVS)',
      'M.findWithDefault N K (M.fromList KVS)', 'M.toDescList (M.fromList KVS)', 'M.mapKeys id (M.fromList KVS)',
      'S.insert K (S.fromList KS)', 'S.fromList KS', 'S.union (S.fromList KS) (S.fromList KS)', 'S.toList (S.fromList KS)',
      'S.fromAscList (sort KS)', 'S.intersection (S.fromList KS) (S.fromList KS)', 'S.findMin (S.insert K (S.fromList KS))',
      'S.elems (S.map id (S.fromList KS))', 'S.member K (S.fromList KS)', 'S.lookupMin (S.fromList KS)',
      'max K K', 'min K K', 'maximum (K : KS)', 'minimum (K : KS)', 'maximumBy compare (K : KS)', 'minimumBy compare (K : KS)',
      'sort KS', 'sortBy compare KS', 'sortOn id KS', 'reverse (sort KS)', 'nub KS', 'union KS KS', 'intersect KS KS',
      'KS \\\\ KS', 'group (sort KS)', 'insert K KS', 'delete K KS', 'elem K KS', 'lookup K KVS', 'nubBy (==) KS',
      'groupBy (==) KS', 'compare K K', 'K == K', 'sortOn negate [N, N, N]', 'maximumBy (comparing snd) KVS'
    ].freeze

    def probe
      # One pass, so a generated key's K is not substituted again.
      pick(TEMPLATES).gsub(/KVS|KS|\bK\b|\bN\b/) do |m|
        case m
        when 'KVS' then kvs
        when 'KS' then ks
        when 'K' then k
        else @r.rand(0..9).to_s
        end
      end
    end
  end
end
