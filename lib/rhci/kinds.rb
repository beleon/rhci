# frozen_string_literal: true

module Rhci
  # Kind inference, as GHC2021 does it (PolyKinds): a kind is :star,
  # :constraint, [:arr, k1, k2], or [:var, i] inside a generalised kind.
  # A declaration group's kinds are inferred by unification; what stays
  # open is generalised (`data P a = P` is `k -> *`), so each use
  # instantiates it afresh. Signatures, annotations and instance heads are
  # checked against the declared kinds. Declared kinds are plain data
  # (TyInfo#kind, ClassInfo#param_kind) and live in the snapshot.
  class Kinds
    include AST

    # A kind variable during inference.
    class Meta
      attr_accessor :ref
    end

    def initialize(source = '<interactive>')
      @source = source
      @group = {}
      @group_classes = {}
    end

    # (Not inject: mruby's takes a Symbol initial value for an operator.)
    def self.arrows(args, res)
      k = res
      i = args.length - 1
      while i >= 0
        k = [:arr, args[i], k]
        i -= 1
      end
      k
    end

    # ---- declarations ---------------------------------------------------------------

    def declarations(tyinfos, classes)
      tyinfos.each do |ti|
        ps = ti.params.map { Meta.new }
        @group[ti] = [ps, ti.synonym ? Meta.new : :star]
      end
      classes.each { |ci| @group_classes[ci] = Meta.new }
      tyinfos.each do |ti|
        ps, res = @group[ti]
        env = {}
        ti.params.each_with_index { |p, i| env[p] = ps[i] }
        if ti.synonym
          unify(res, infer(ti.synonym[1], env, false), ti.synonym[1])
        else
          ti.cons.each { |c| (c.field_types || []).each { |ft| check(ft, :star, env, false) } }
        end
      end
      classes.each do |ci|
        k = @group_classes[ci]
        (ci.supers || []).each { |sup| unify(k, class_kind(sup), ci.tok) }
        (ci.sigs || {}).each_value { |sig| check(sig.type, :star, { ci.tyvar => k }, true) }
      end
      tyinfos.each do |ti|
        ps, res = @group[ti]
        ti.kind = generalize(Kinds.arrows(ps, res))
      end
      classes.each { |ci| ci.param_kind = generalize(@group_classes[ci]) }
      @group = {}
      @group_classes = {}
    end

    # A signature or annotation: kind * (its context checked too). vars:
    # kinds of type variables already in scope (a class's variable).
    def signature(ast, vars = {})
      check(ast, :star, vars.dup, true)
    end

    # An instance head (with its type variables) at the class's kind.
    def instance_head(ast, klass)
      check(ast, class_kind(klass), {}, true)
    end

    # The kind :kind shows for a type expression.
    def kind_of(ast)
      generalize(infer(ast, {}, false))
    end

    # ---- inference ------------------------------------------------------------------

    def check(ast, kind, env, extend)
      unify(kind, infer(ast, env, extend), ast)
    end

    def infer(t, env, extend)
      case t
      when TVar
        k = env[t.name]
        return k if k
        return (env[t.name] = Meta.new) if extend

        raise Error.new(:scope, "Not in scope: type variable ‘#{t.name}’", t.tok&.line, t.tok&.col, @source)
      when TCon then tycon_kind(t)
      when TApp
        k = infer(t.fn, env, extend)
        t.args.each do |a|
          r = Meta.new
          ka = infer(a, env, extend)
          unify(k, [:arr, ka, r], a, t.fn)
          k = r
        end
        k
      when TFun
        check(t.from, :star, env, extend)
        check(t.to, :star, env, extend)
        :star
      when TList
        check(t.elem, :star, env, extend)
        :star
      when TTuple
        t.elems.each { |e| check(e, :star, env, extend) }
        :star
      when TQual
        (t.ref || []).each { |klass, ct| check(ct, class_kind(klass), env, extend) unless klass == :eq }
        infer(t.type, env, extend)
      else Meta.new
      end
    end

    def tycon_kind(t)
      n = t.ref
      return [:arr, class_kind(n.klass), :constraint] if n.respond_to?(:kind) && n.kind == :class && n.klass

      ti = n.respond_to?(:tyinfo) ? n.tyinfo : nil
      return Meta.new unless ti # reported by the type conversion

      if @group.key?(ti)
        ps, res = @group[ti]
        return Kinds.arrows(ps, res)
      end
      return instantiate(ti.kind) if ti.kind

      Kinds.arrows(Array.new(ti.tcon.arity, :star), :star)
    end

    def class_kind(ci)
      return @group_classes[ci] if @group_classes.key?(ci)
      return instantiate(ci.param_kind) if ci.param_kind

      ci.var_arity.to_i.zero? ? :star : Kinds.arrows(Array.new(ci.var_arity, :star), :star)
    end

    def prune(k)
      k = k.ref while k.is_a?(Meta) && k.ref
      k
    end

    # node: where the kinds meet; head: the type applied there (if any).
    def unify(a, b, node, head = nil)
      a = prune(a)
      b = prune(b)
      return if a.equal?(b)

      if a.is_a?(Meta)
        mismatch(a, b, node, head) if occurs?(a, b)
        a.ref = b
      elsif b.is_a?(Meta)
        mismatch(a, b, node, head) if occurs?(b, a)
        b.ref = a
      elsif a.is_a?(Array) && b.is_a?(Array) && a[0] == :arr && b[0] == :arr
        unify(a[1], b[1], node, head)
        unify(a[2], b[2], node, head)
      elsif a != b
        mismatch(a, b, node, head)
      end
    end

    def occurs?(m, k)
      k = prune(k)
      return true if k.equal?(m)

      k.is_a?(Array) && k[0] == :arr && (occurs?(m, k[1]) || occurs?(m, k[2]))
    end

    def mismatch(a, b, node, head)
      what = head ? "‘#{Kinds.text(head)}’ applied to ‘#{Kinds.text(node)}’" : "‘#{Kinds.text(node)}’"
      raise Error.new(:compile, "Expected kind ‘#{Kinds.show(zonk(a))}’, but #{what} has kind ‘#{Kinds.show(zonk(b))}’",
                      node.tok&.line, node.tok&.col, @source)
    end

    def zonk(k, names = {})
      k = prune(k)
      case k
      when Meta then names[k] ||= [:var, names.length]
      when Array then k[0] == :arr ? [:arr, zonk(k[1], names), zonk(k[2], names)] : k
      else k
      end
    end

    def generalize(k)
      zonk(k, {})
    end

    def instantiate(k, metas = {})
      case k
      when Array
        return metas[k[1]] ||= Meta.new if k[0] == :var

        [:arr, instantiate(k[1], metas), instantiate(k[2], metas)]
      else k
      end
    end

    def self.text(t)
      case t
      when TCon, TVar then t.name
      when TList then "[#{text(t.elem)}]"
      when TTuple then "(#{t.elems.map { |e| text(e) }.join(', ')})"
      when TFun then "#{text(t.from)} -> #{text(t.to)}"
      when TApp then ([text(t.fn)] + t.args.map { |a| a.is_a?(TApp) || a.is_a?(TFun) ? "(#{text(a)})" : text(a) }).join(' ')
      else '?'
      end
    end

    # GHC's spelling: `*`, `Constraint`, variables k (one) or k1, k2, ...
    # in order of appearance.
    def self.show(k)
      vars = []
      collect = lambda do |x|
        if x.is_a?(Array) && x[0] == :var
          vars << x[1] unless vars.include?(x[1])
        elsif x.is_a?(Array)
          collect.call(x[1])
          collect.call(x[2])
        end
      end
      collect.call(k)
      show_kind(k, vars)
    end

    def self.show_kind(k, vars)
      case k
      when :star then '*'
      when :constraint then 'Constraint'
      when Meta then 'k0'
      when Array
        if k[0] == :var
          vars.length == 1 ? 'k' : "k#{vars.index(k[1]) + 1}"
        else
          from = show_kind(k[1], vars)
          from = "(#{from})" if k[1].is_a?(Array) && k[1][0] == :arr
          "#{from} -> #{show_kind(k[2], vars)}"
        end
      else k.to_s
      end
    end
  end
end
