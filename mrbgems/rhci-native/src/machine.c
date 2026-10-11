/* The evaluation loop of Rhci::VM::Machine (lib/rhci/vm.rb, `run_ruby`)
 * in C, for the mruby builds. It is a line-by-line port working on the
 * same Ruby objects: code (plain Arrays, see vm.rb), thunks, closures and
 * constructor values (Array subclasses), the segmented FrameStack, and the
 * machine's Ruby primitives, so everything around the loop is shared.
 * The Ruby loop stays the reference (CRuby runs it); a change to one is a
 * change to both.
 *
 * Integer primitives on fixnums run here; anything else (bignums, other
 * primitives) calls the Ruby method.
 *
 * GC: mruby's collector does not scan C locals. At the top of every step
 * the GC arena is reset and the loop's registers (expr, locals, env,
 * value) are protected again; everything else a step touches is either
 * reachable from them or freshly allocated (and so in the arena).
 */
#include <string.h>

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/error.h>
#include <mruby/hash.h>
#include <mruby/string.h>
#include <mruby/variable.h>

/* opcodes, as in vm.rb */
enum { OP_LOCAL, OP_ENV, OP_GLOBAL, OP_VALUE, OP_APP, OP_LET, OP_CASE, OP_CON, OP_PRIM, OP_STR };

/* code bodies: [arity, captures, nlocals, body, name] */
enum { CODE_ARITY, CODE_CAPTURES, CODE_NLOCALS, CODE_BODY };

/* An element of an Array known to be long enough (code, frames). */
#define AT(a, i) (RARRAY_PTR(a)[i])

#define ENV_THUNK 2
#define ENV_FUN 1
#define SEGMENT 1024

static mrb_sym s_op, s_index, s_cell, s_value, s_fn, s_args, s_binds, s_body, s_scrut, s_binder,
  s_con_alts, s_lit_alts, s_default, s_con, s_meth, s_strict, s_cps, s_arity, s_captures, s_nlocals,
  s_tag, s_nullary, s_top, s_full, s_length, s_steps, s_next_check, s_stack, s_fun, s_payload;
static mrb_sym m_value;
static mrb_sym y_pending, y_value, y_blackhole, y_raised, y_thunk, y_funk, y_conk, y_str;
static mrb_sym p_integerAdd, p_integerSub, p_integerMul, p_integerEq, p_integerLt, p_integerLe,
  p_integerGt, p_integerGe, p_intAdd, p_intSub, p_intMul, p_charEq, p_ord, p_chr,
  p_integerQuot, p_integerRem, p_integerDiv, p_integerMod, p_intRem, p_intMod, p_intToInteger,
  p_integerToInt, p_intNegate, p_integerNegate, p_doubleNegate, p_doubleAdd, p_doubleSub, p_doubleMul,
  p_doubleDiv, p_doubleEq, p_doubleLt, p_doubleLe, p_doubleGt, p_doubleGe;

struct classes {
  struct RClass *thunk, *string_thunk, *fun, *pap, *con_value, *hs_exception, *limit, *lazy_cell;
  mrb_value nil_v, true_v, false_v, cons, case_frame;
};
static struct classes K;
static int ready = 0;

#define IV(o, s) mrb_iv_get(mrb, (o), (s))
#define PROTECT(v) mrb_gc_protect(mrb, (v))
#define CLASS_OF(v) (mrb_obj_ptr(v)->c)

static int
is_thunk(mrb_value v)
{
  if (!mrb_array_p(v)) return 0;
  struct RClass *c = CLASS_OF(v);
  return c == K.thunk || c == K.string_thunk;
}

static void
setup(mrb_state *mrb)
{
  struct RClass *rhci = mrb_module_get(mrb, "Rhci");
  struct RClass *vm = mrb_module_get_under(mrb, rhci, "VM");
  struct RClass *snapshot = mrb_module_get_under(mrb, rhci, "Snapshot");
  K.thunk = mrb_class_get_under(mrb, vm, "Thunk");
  K.string_thunk = mrb_class_get_under(mrb, vm, "StringThunk");
  K.fun = mrb_class_get_under(mrb, vm, "Fun");
  K.pap = mrb_class_get_under(mrb, vm, "PAP");
  K.con_value = mrb_class_get_under(mrb, vm, "ConValue");
  K.case_frame = mrb_const_get(mrb, mrb_obj_value(vm), mrb_intern_lit(mrb, "CASE_FRAME"));
  K.hs_exception = mrb_class_get_under(mrb, vm, "HsException");
  K.limit = mrb_class_get_under(mrb, vm, "LimitExceeded");
  K.lazy_cell = mrb_class_get_under(mrb, snapshot, "LazyCell");
  struct RClass *builtins = mrb_module_get_under(mrb, vm, "Builtins");
  mrb_value b = mrb_obj_value(builtins);
  K.nil_v = mrb_const_get(mrb, b, mrb_intern_lit(mrb, "NIL_V"));
  K.true_v = mrb_const_get(mrb, b, mrb_intern_lit(mrb, "TRUE_V"));
  K.false_v = mrb_const_get(mrb, b, mrb_intern_lit(mrb, "FALSE_V"));
  K.cons = mrb_const_get(mrb, b, mrb_intern_lit(mrb, "CONS"));
  ready = 1;
}

/* ---- the frame stack (VM::FrameStack's representation) ------------------ */

/* While the loop runs, the stack's top segment and length are kept here;
 * @top is updated whenever the segment changes (so the GC sees it), and
 * @length is written back before Ruby can read it (sync_stack). */
struct fstack {
  mrb_value obj, top, full;
  mrb_int len;
};

static void
open_stack(mrb_state *mrb, struct fstack *st, mrb_value obj)
{
  st->obj = obj;
  st->top = IV(obj, s_top);
  st->full = IV(obj, s_full);
  st->len = mrb_integer(IV(obj, s_length));
}

static void
sync_stack(mrb_state *mrb, struct fstack *st)
{
  mrb_iv_set(mrb, st->obj, s_length, mrb_int_value(mrb, st->len));
}

static void
stack_push(mrb_state *mrb, struct fstack *st, mrb_value frame)
{
  if (RARRAY_LEN(st->top) == SEGMENT) {
    mrb_ary_push(mrb, st->full, st->top);
    st->top = mrb_ary_new_capa(mrb, SEGMENT);
    mrb_iv_set(mrb, st->obj, s_top, st->top);
  }
  mrb_ary_push(mrb, st->top, frame);
  st->len++;
}

static mrb_value
stack_pop(mrb_state *mrb, struct fstack *st)
{
  if (st->len == 0) return mrb_nil_value();
  if (RARRAY_LEN(st->top) == 0) {
    st->top = mrb_ary_pop(mrb, st->full);
    mrb_iv_set(mrb, st->obj, s_top, st->top);
  }
  st->len--;
  mrb_value f = mrb_ary_pop(mrb, st->top);
  mrb_gc_protect(mrb, f);
  return f;
}

/* ---- values -------------------------------------------------------------- */

/* A fresh instance of an Array subclass with n nil slots. */
static mrb_value
new_array_of(mrb_state *mrb, struct RClass *c, mrb_int n)
{
  mrb_value a = mrb_ary_new_capa(mrb, n);
  mrb_obj_ptr(a)->c = c;
  if (n > 0) mrb_ary_set(mrb, a, n - 1, mrb_nil_value());
  return a;
}

/* A Cell's or ValueAtom's value (a LazyCell decodes on first read). */
static mrb_value
cell_value(mrb_state *mrb, mrb_value cell)
{
  mrb_value v = IV(cell, s_value);
  if (mrb_nil_p(v) && CLASS_OF(cell) == K.lazy_cell) v = mrb_funcall_argv(mrb, cell, m_value, 0, NULL);
  return v;
}

/* An encoded atom's value: slot i >= 0, environment slot -i-1, or an
 * object with a value (Cell, ValueAtom). */
static mrb_value
atom(mrb_state *mrb, mrb_value a, mrb_value locals, mrb_value env)
{
  if (mrb_integer_p(a)) {
    mrb_int i = mrb_integer(a);
    return i >= 0 ? mrb_ary_ref(mrb, locals, i) : mrb_ary_ref(mrb, env, -i - 1);
  }
  return cell_value(mrb, a);
}

static mrb_value
gather(mrb_state *mrb, mrb_value atoms, mrb_value locals, mrb_value env)
{
  mrb_int n = RARRAY_LEN(atoms);
  mrb_value out = mrb_ary_new_capa(mrb, n);
  for (mrb_int i = 0; i < n; i++) mrb_ary_push(mrb, out, atom(mrb, RARRAY_PTR(atoms)[i], locals, env));
  return out;
}

static mrb_value
build_data(mrb_state *mrb, mrb_value con, mrb_value atoms, mrb_value locals, mrb_value env)
{
  mrb_int n = RARRAY_LEN(atoms);
  mrb_value d = new_array_of(mrb, K.con_value, n + 1);
  mrb_ary_set(mrb, d, 0, con);
  for (mrb_int i = 0; i < n; i++) mrb_ary_set(mrb, d, i + 1, atom(mrb, RARRAY_PTR(atoms)[i], locals, env));
  return d;
}

static void
raise_hs(mrb_state *mrb, const char *msg)
{
  mrb_value s = mrb_str_new_cstr(mrb, msg);
  mrb_exc_raise(mrb, mrb_obj_new(mrb, K.hs_exception, 1, &s));
}

/* xc: [OP_CASE, scrut, binder, con_alts, lit_alts, default] */
static mrb_value
select_alt(mrb_state *mrb, mrb_value xc, mrb_value value, mrb_value locals)
{
  mrb_value con_alts = AT(xc, 3);
  if (!mrb_nil_p(con_alts)) {
    mrb_int tag = mrb_integer(IV(mrb_ary_ref(mrb, value, 0), s_tag));
    mrb_value alt = mrb_ary_ref(mrb, con_alts, tag);
    if (!mrb_nil_p(alt)) {
      mrb_value slots = AT(alt, 0);
      mrb_int n = RARRAY_LEN(slots);
      for (mrb_int i = 0; i < n; i++) {
        mrb_value s = AT(slots, i);
        if (!mrb_nil_p(s)) mrb_ary_set(mrb, locals, mrb_integer(s), mrb_ary_ref(mrb, value, i + 1));
      }
      return AT(alt, 1);
    }
  }
  else {
    mrb_value lit_alts = AT(xc, 4);
    if (!mrb_nil_p(lit_alts)) {
      mrb_value body = mrb_hash_get(mrb, lit_alts, value);
      if (!mrb_nil_p(body)) return body;
    }
  }
  mrb_value d = AT(xc, 5);
  if (!mrb_nil_p(d)) return d;
  raise_hs(mrb, "machine: no matching case alternative");
  return mrb_nil_value();
}

static void
fill(mrb_state *mrb, mrb_value obj, mrb_int offset, mrb_value atoms, mrb_value locals, mrb_value env)
{
  mrb_int n = RARRAY_LEN(atoms);
  for (mrb_int i = 0; i < n; i++) mrb_ary_set(mrb, obj, offset + i, atom(mrb, RARRAY_PTR(atoms)[i], locals, env));
}

static mrb_value
new_thunk(mrb_state *mrb, mrb_value code)
{
  mrb_value t = new_array_of(mrb, K.thunk, ENV_THUNK + RARRAY_LEN(AT(code, CODE_CAPTURES)));
  mrb_ary_set(mrb, t, 0, mrb_symbol_value(y_pending));
  mrb_ary_set(mrb, t, 1, code);
  return t;
}

static mrb_value
new_string_thunk(mrb_state *mrb, mrb_value cps, mrb_int index)
{
  mrb_value t = new_array_of(mrb, K.string_thunk, 4);
  mrb_ary_set(mrb, t, 0, mrb_symbol_value(y_pending));
  mrb_ary_set(mrb, t, 2, cps);
  mrb_ary_set(mrb, t, 3, mrb_int_value(mrb, index));
  return t;
}

/* Two phases, so a recursive group can refer to itself. */
static void
allocate(mrb_state *mrb, mrb_value binds, mrb_value locals, mrb_value env)
{
  mrb_int n = RARRAY_LEN(binds);
  for (mrb_int i = 0; i < n; i++) {
    mrb_value b = RARRAY_PTR(binds)[i];
    mrb_int slot = mrb_integer(mrb_ary_ref(mrb, b, 0));
    mrb_sym kind = mrb_symbol(mrb_ary_ref(mrb, b, 1));
    mrb_value payload = mrb_ary_ref(mrb, b, 2);
    mrb_value v;
    if (kind == y_thunk) v = new_thunk(mrb, payload);
    else if (kind == y_funk) {
      v = new_array_of(mrb, K.fun, ENV_FUN + RARRAY_LEN(AT(payload, CODE_CAPTURES)));
      mrb_ary_set(mrb, v, 0, payload);
    }
    else if (kind == y_conk) { /* payload: [ConInfo, atoms, shared value if nullary] */
      mrb_int arity = RARRAY_LEN(AT(payload, 1));
      if (arity == 0) v = AT(payload, 2);
      else {
        v = new_array_of(mrb, K.con_value, arity + 1);
        mrb_ary_set(mrb, v, 0, AT(payload, 0));
      }
    }
    else if (kind == y_str) v = new_string_thunk(mrb, payload, 0);
    else v = payload;
    mrb_ary_set(mrb, locals, slot, v);
  }
  for (mrb_int i = 0; i < n; i++) {
    mrb_value b = RARRAY_PTR(binds)[i];
    mrb_int slot = mrb_integer(mrb_ary_ref(mrb, b, 0));
    mrb_sym kind = mrb_symbol(mrb_ary_ref(mrb, b, 1));
    mrb_value payload = mrb_ary_ref(mrb, b, 2);
    mrb_value obj = mrb_ary_ref(mrb, locals, slot);
    if (kind == y_thunk) fill(mrb, obj, ENV_THUNK, AT(payload, CODE_CAPTURES), locals, env);
    else if (kind == y_funk) fill(mrb, obj, ENV_FUN, AT(payload, CODE_CAPTURES), locals, env);
    else if (kind == y_conk) {
      mrb_value atoms = mrb_ary_ref(mrb, payload, 1);
      if (RARRAY_LEN(atoms) > 0) fill(mrb, obj, 1, atoms, locals, env);
    }
  }
}

static void
settle(mrb_state *mrb, mrb_value t, mrb_sym state, mrb_value value)
{
  mrb_ary_set(mrb, t, 0, mrb_symbol_value(state));
  mrb_ary_set(mrb, t, 1, value);
  mrb_int n = RARRAY_LEN(t);
  for (mrb_int i = ENV_THUNK; i < n; i++) RARRAY_PTR(t)[i] = mrb_nil_value();
}

static mrb_value
unpack(mrb_state *mrb, mrb_value st)
{
  if (mrb_symbol(mrb_ary_ref(mrb, st, 0)) == y_value) return mrb_ary_ref(mrb, st, 1);
  mrb_value cps = mrb_ary_ref(mrb, st, 2);
  mrb_int i = mrb_integer(mrb_ary_ref(mrb, st, 3));
  mrb_value v;
  if (i >= RARRAY_LEN(cps)) v = K.nil_v;
  else {
    v = new_array_of(mrb, K.con_value, 3);
    mrb_ary_set(mrb, v, 0, K.cons);
    mrb_ary_set(mrb, v, 1, RARRAY_PTR(cps)[i]);
    mrb_ary_set(mrb, v, 2, new_string_thunk(mrb, cps, i + 1));
  }
  mrb_ary_set(mrb, st, 0, mrb_symbol_value(y_value));
  mrb_ary_set(mrb, st, 1, v);
  mrb_ary_set(mrb, st, 2, mrb_nil_value());
  return v;
}

/* ---- primitives ------------------------------------------------------------ */

static mrb_value
boolv(int b)
{
  return b ? K.true_v : K.false_v;
}

/* Double primitives, as the Ruby ones compute them (IEEE arithmetic;
 * comparisons are false with NaN). */
static int
fast_double2(mrb_state *mrb, mrb_sym p, mrb_value x, mrb_value y, mrb_value *out)
{
  mrb_float a = mrb_float(x), b = mrb_float(y);
  if (p == p_doubleAdd) *out = mrb_float_value(mrb, a + b);
  else if (p == p_doubleSub) *out = mrb_float_value(mrb, a - b);
  else if (p == p_doubleMul) *out = mrb_float_value(mrb, a * b);
  else if (p == p_doubleDiv) *out = mrb_float_value(mrb, a / b);
  else if (p == p_doubleEq) *out = boolv(a == b);
  else if (p == p_doubleLt) *out = boolv(a < b);
  else if (p == p_doubleLe) *out = boolv(a <= b);
  else if (p == p_doubleGt) *out = boolv(a > b);
  else if (p == p_doubleGe) *out = boolv(a >= b);
  else return 0;
  return 1;
}

/* Integer primitives on two fixnums, done here; returns 0 if the Ruby
 * primitive must run (another primitive, a bignum, an overflow, or a
 * division by zero, which the Ruby primitive reports). */
static int
fast_prim2(mrb_state *mrb, mrb_sym p, mrb_value x, mrb_value y, mrb_value *out)
{
  if (mrb_float_p(x) && mrb_float_p(y)) return fast_double2(mrb, p, x, y, out);
  if (!mrb_integer_p(x) || !mrb_integer_p(y)) return 0;
  mrb_int a = mrb_integer(x), b = mrb_integer(y), r;
  if (p == p_integerQuot || p == p_integerRem || p == p_integerDiv || p == p_integerMod ||
      p == p_intRem || p == p_intMod) {
    if (b == 0 || (a == INT64_MIN && b == -1)) return 0;
    if (p == p_integerQuot) r = a / b;
    else if (p == p_integerRem || p == p_intRem) r = a % b;
    else if (p == p_integerDiv) {
      r = a / b;
      if (a % b != 0 && ((a < 0) != (b < 0))) r--;
    }
    else {
      r = a % b;
      if (r != 0 && ((r < 0) != (b < 0))) r += b;
    }
    *out = mrb_int_value(mrb, r);
    return 1;
  }
  if (p == p_integerAdd) { if (__builtin_add_overflow(a, b, &r)) return 0; *out = mrb_int_value(mrb, r); }
  else if (p == p_integerSub) { if (__builtin_sub_overflow(a, b, &r)) return 0; *out = mrb_int_value(mrb, r); }
  else if (p == p_integerMul) { if (__builtin_mul_overflow(a, b, &r)) return 0; *out = mrb_int_value(mrb, r); }
  /* Int wraps at 64 bits: two's complement arithmetic on unsigned. */
  else if (p == p_intAdd) *out = mrb_int_value(mrb, (mrb_int)((uint64_t)a + (uint64_t)b));
  else if (p == p_intSub) *out = mrb_int_value(mrb, (mrb_int)((uint64_t)a - (uint64_t)b));
  else if (p == p_intMul) *out = mrb_int_value(mrb, (mrb_int)((uint64_t)a * (uint64_t)b));
  else if (p == p_integerEq || p == p_charEq) *out = boolv(a == b);
  else if (p == p_integerLt) *out = boolv(a < b);
  else if (p == p_integerLe) *out = boolv(a <= b);
  else if (p == p_integerGt) *out = boolv(a > b);
  else if (p == p_integerGe) *out = boolv(a >= b);
  else return 0;
  return 1;
}

static int
fast_prim1(mrb_state *mrb, mrb_sym p, mrb_value x, mrb_value *out)
{
  if (mrb_integer_p(x)) {
    mrb_int a = mrb_integer(x);
    if (p == p_ord || p == p_intToInteger || p == p_integerToInt) *out = x;
    else if (p == p_intNegate) *out = mrb_int_value(mrb, (mrb_int)(0 - (uint64_t)a));
    else if (p == p_integerNegate && a != INT64_MIN) *out = mrb_int_value(mrb, -a);
    else return 0;
    return 1;
  }
  if (mrb_float_p(x) && p == p_doubleNegate) {
    *out = mrb_float_value(mrb, -mrb_float(x));
    return 1;
  }
  return 0;
}

/* xp: [OP_PRIM, method, atoms, strict, name] */
static mrb_value
prim(mrb_state *mrb, mrb_value self, mrb_value xp, mrb_value locals, mrb_value env)
{
  mrb_value pa = AT(xp, 2);
  mrb_bool strict = mrb_test(AT(xp, 3));
  mrb_sym meth = mrb_symbol(AT(xp, 1));
  mrb_value argv[2];
  mrb_int n = RARRAY_LEN(pa);
  argv[0] = atom(mrb, RARRAY_PTR(pa)[0], locals, env);
  if (n == 2) argv[1] = atom(mrb, RARRAY_PTR(pa)[1], locals, env);
  if (strict) {
    if (is_thunk(argv[0]) || (n == 2 && is_thunk(argv[1]))) {
      mrb_funcall_argv(mrb, self, mrb_intern_lit(mrb, "bad_operand"), 1, &xp);
    }
    mrb_value r;
    if (n == 2 && fast_prim2(mrb, meth, argv[0], argv[1], &r)) return r;
    if (n == 1 && fast_prim1(mrb, meth, argv[0], &r)) return r;
  }
  return mrb_funcall_argv(mrb, self, meth, n == 2 ? 2 : 1, argv);
}

/* ---- the loop ---------------------------------------------------------------- */

struct run_args {
  mrb_value self, expr, locals, env;
  mrb_int base;
  mrb_int steps;       /* the machine's @steps, written back on every exit */
  struct fstack stack; /* the machine's @stack, synced likewise */
};

static mrb_value
run_body(mrb_state *mrb, void *ud)
{
  struct run_args *ra = (struct run_args *)ud;
  mrb_value self = ra->self, expr = ra->expr, locals = ra->locals, env = ra->env;
  mrb_int base = ra->base;
  struct fstack *stack = &ra->stack;
  mrb_value value = mrb_nil_value();
  int evaluating = 1;
  mrb_int next_check = mrb_integer(IV(self, s_next_check));
  int ai = mrb_gc_arena_save(mrb);

  for (;;) {
    /* Everything the loop allocates is in the GC arena; it is reset now
     * and then, re-protecting the registers. Between resets, a value a
     * register reads out of another object is protected as it is read
     * (PROTECT), since that object may be dropped. */
    if (mrb->gc.arena_idx - ai > 512) {
      mrb_gc_arena_restore(mrb, ai);
      mrb_gc_protect(mrb, expr);
      mrb_gc_protect(mrb, locals);
      mrb_gc_protect(mrb, env);
      mrb_gc_protect(mrb, value);
    }
    if (evaluating) {
      ra->steps++;
      if (ra->steps >= next_check) {
        mrb_iv_set(mrb, self, s_steps, mrb_int_value(mrb, ra->steps));
        sync_stack(mrb, stack);
        mrb_funcall_argv(mrb, self, mrb_intern_lit(mrb, "check_limits"), 0, NULL);
        next_check = mrb_integer(IV(self, s_next_check));
      }
      mrb_int op = mrb_integer(AT(expr, 0));
      if (op <= OP_VALUE) {
        mrb_value v;
        if (op == OP_LOCAL) v = mrb_ary_ref(mrb, locals, mrb_integer(AT(expr, 1)));
        else if (op == OP_ENV) v = mrb_ary_ref(mrb, env, mrb_integer(AT(expr, 1)));
        else if (op == OP_GLOBAL) v = cell_value(mrb, AT(expr, 1));
        else v = AT(expr, 1);
        if (is_thunk(v)) {
          mrb_sym state = mrb_symbol(mrb_ary_ref(mrb, v, 0));
          if (state == y_value) {
            value = mrb_ary_ref(mrb, v, 1);
            PROTECT(value);
            evaluating = 0;
          }
          else if (state == y_pending) {
            if (CLASS_OF(v) == K.string_thunk) {
              value = unpack(mrb, v);
              PROTECT(value);
              evaluating = 0;
            }
            else {
              mrb_ary_set(mrb, v, 0, mrb_symbol_value(y_blackhole));
              stack_push(mrb, stack, v);
              mrb_value code = mrb_ary_ref(mrb, v, 1);
              env = v;
              mrb_int n = mrb_integer(AT(code, CODE_NLOCALS));
              locals = n == 0 ? mrb_nil_value() : mrb_ary_new_capa(mrb, n);
              if (n > 0) mrb_ary_set(mrb, locals, n - 1, mrb_nil_value());
              expr = AT(code, CODE_BODY);
            }
          }
          else if (state == y_blackhole) raise_hs(mrb, "<<loop>>");
          else mrb_exc_raise(mrb, mrb_ary_ref(mrb, v, 1));
        }
        else {
          value = v;
          PROTECT(value);
          evaluating = 0;
        }
      }
      else if (op == OP_APP) {
        mrb_value f = AT(expr, 1);
        mrb_int fo = mrb_integer(AT(f, 0));
        mrb_value fv;
        if (fo == OP_GLOBAL) fv = cell_value(mrb, AT(f, 1));
        else if (fo == OP_LOCAL) fv = mrb_ary_ref(mrb, locals, mrb_integer(AT(f, 1)));
        else if (fo == OP_ENV) fv = mrb_ary_ref(mrb, env, mrb_integer(AT(f, 1)));
        else fv = AT(f, 1);
        if (is_thunk(fv) && mrb_symbol(mrb_ary_ref(mrb, fv, 0)) == y_value) fv = mrb_ary_ref(mrb, fv, 1);
        mrb_value atoms = AT(expr, 2);
        mrb_int n = RARRAY_LEN(atoms);
        mrb_value code;
        if (mrb_array_p(fv) && CLASS_OF(fv) == K.fun &&
            mrb_integer(AT(code = AT(fv, 0), CODE_ARITY)) == n) {
          /* Known saturated call: arguments straight into the callee's locals. */
          mrb_int nl = mrb_integer(AT(code, CODE_NLOCALS));
          mrb_value l = mrb_ary_new_capa(mrb, nl);
          if (nl > 0) mrb_ary_set(mrb, l, nl - 1, mrb_nil_value());
          for (mrb_int i = 0; i < n; i++) mrb_ary_set(mrb, l, i, atom(mrb, RARRAY_PTR(atoms)[i], locals, env));
          locals = l;
          env = fv;
          PROTECT(env);
          expr = AT(code, CODE_BODY);
        }
        else {
          stack_push(mrb, stack, gather(mrb, atoms, locals, env));
          expr = f;
        }
      }
      else if (op == OP_CASE) {
        mrb_value sc = AT(expr, 1);
        mrb_int so = mrb_integer(AT(sc, 0));
        mrb_value sv = mrb_undef_value();
        if (so <= OP_VALUE) {
          if (so == OP_LOCAL) sv = mrb_ary_ref(mrb, locals, mrb_integer(AT(sc, 1)));
          else if (so == OP_ENV) sv = mrb_ary_ref(mrb, env, mrb_integer(AT(sc, 1)));
          else if (so == OP_GLOBAL) sv = cell_value(mrb, AT(sc, 1));
          else sv = AT(sc, 1);
          if (is_thunk(sv)) sv = mrb_symbol(mrb_ary_ref(mrb, sv, 0)) == y_value ? mrb_ary_ref(mrb, sv, 1) : mrb_undef_value();
        }
        else if (so == OP_PRIM && mrb_test(AT(sc, 3))) {
          sv = prim(mrb, self, sc, locals, env);
        }
        if (mrb_undef_p(sv)) {
          stack_push(mrb, stack, env);
          stack_push(mrb, stack, locals);
          stack_push(mrb, stack, expr);
          stack_push(mrb, stack, K.case_frame);
          expr = sc;
        }
        else {
          mrb_value binder = AT(expr, 2);
          if (!mrb_nil_p(binder)) mrb_ary_set(mrb, locals, mrb_integer(binder), sv);
          expr = select_alt(mrb, expr, sv, locals);
        }
      }
      else if (op == OP_LET) {
        allocate(mrb, AT(expr, 1), locals, env);
        expr = AT(expr, 2);
      }
      else if (op == OP_CON) {
        mrb_value atoms = AT(expr, 2);
        value = RARRAY_LEN(atoms) == 0 ? AT(expr, 3) : build_data(mrb, AT(expr, 1), atoms, locals, env);
        evaluating = 0;
      }
      else if (op == OP_PRIM) {
        value = prim(mrb, self, expr, locals, env);
        PROTECT(value);
        evaluating = 0;
      }
      else if (op == OP_STR) {
        value = unpack(mrb, new_string_thunk(mrb, AT(expr, 1), 0));
        evaluating = 0;
      }
      else {
        mrb_raise(mrb, E_RUNTIME_ERROR, "machine: unknown code");
      }
    }
    else {
      if (stack->len == base) {
        mrb_iv_set(mrb, self, s_steps, mrb_int_value(mrb, ra->steps));
        sync_stack(mrb, stack);
        return value;
      }
      mrb_value frame = stack_pop(mrb, stack);
      if (mrb_obj_eq(mrb, frame, K.case_frame)) {
        frame = stack_pop(mrb, stack);
        locals = stack_pop(mrb, stack);
        env = stack_pop(mrb, stack);
        mrb_value binder = AT(frame, 2);
        if (!mrb_nil_p(binder)) mrb_ary_set(mrb, locals, mrb_integer(binder), value);
        expr = select_alt(mrb, frame, value, locals);
        evaluating = 1;
      }
      else if (is_thunk(frame)) {
        settle(mrb, frame, y_value, value);
      }
      else { /* pending arguments */
        mrb_value fun = value;
        mrb_value args = frame;
        if (!mrb_immediate_p(fun) && CLASS_OF(fun) == K.pap) {
          mrb_value joined = mrb_ary_dup(mrb, IV(fun, s_args));
          mrb_ary_concat(mrb, joined, args);
          args = joined;
          fun = IV(fun, s_fun);
          PROTECT(fun);
        }
        if (!mrb_array_p(fun) || CLASS_OF(fun) != K.fun) {
          mrb_raise(mrb, E_RUNTIME_ERROR, "machine: applying a non-function");
        }
        mrb_value code = AT(fun, 0);
        mrb_int n = mrb_integer(AT(code, CODE_ARITY));
        mrb_int len = RARRAY_LEN(args);
        if (len < n) {
          mrb_value pv[2] = { fun, args };
          value = mrb_obj_new(mrb, K.pap, 2, pv);
        }
        else {
          if (len > n) {
            stack_push(mrb, stack, mrb_ary_new_from_values(mrb, len - n, RARRAY_PTR(args) + n));
            args = mrb_ary_new_from_values(mrb, n, RARRAY_PTR(args));
          }
          mrb_int nl = mrb_integer(AT(code, CODE_NLOCALS));
          if (nl > n) mrb_ary_set(mrb, args, nl - 1, mrb_nil_value());
          locals = args;
          env = fun;
          expr = AT(code, CODE_BODY);
          evaluating = 1;
        }
      }
    }
  }
}

/* Machine#run_native(expr, locals, env, base): `run`, in C. Exceptions
 * unwind the frames above base exactly as the Ruby loop does. */
static mrb_value
machine_run_native(mrb_state *mrb, mrb_value self)
{
  struct run_args ra;
  mrb_get_args(mrb, "oooi", &ra.expr, &ra.locals, &ra.env, &ra.base);
  if (!ready) setup(mrb);
  ra.self = self;
  ra.steps = mrb_integer(mrb_iv_get(mrb, self, s_steps));
  open_stack(mrb, &ra.stack, mrb_iv_get(mrb, self, s_stack));
  mrb_bool failed = FALSE;
  mrb_value r = mrb_protect_error(mrb, run_body, &ra, &failed);
  if (failed) {
    mrb_iv_set(mrb, self, s_steps, mrb_int_value(mrb, ra.steps));
    sync_stack(mrb, &ra.stack);
    mrb_value argv[2];
    argv[0] = mrb_int_value(mrb, ra.base);
    if (mrb_obj_is_kind_of(mrb, r, K.hs_exception)) argv[1] = r;
    else argv[1] = mrb_nil_value();
    if (mrb_obj_is_kind_of(mrb, r, K.hs_exception) || mrb_obj_is_kind_of(mrb, r, K.limit)) {
      mrb_funcall_argv(mrb, self, mrb_intern_lit(mrb, "unwind"), 2, argv);
    }
    mrb_exc_raise(mrb, r);
  }
  return r;
}

void rhci_term_init(mrb_state *mrb);
void rhci_bigint_eq_init(mrb_state *mrb);
void rhci_bigint_ops_init(mrb_state *mrb);
void rhci_term_final(mrb_state *mrb);

#define SYM(x) mrb_intern_lit(mrb, x)

void
mrb_rhci_native_gem_init(mrb_state *mrb)
{
  rhci_term_init(mrb);
  rhci_bigint_eq_init(mrb);
  rhci_bigint_ops_init(mrb);
  s_op = SYM("@op"); s_index = SYM("@index"); s_cell = SYM("@cell"); s_value = SYM("@value");
  s_fn = SYM("@fn"); s_args = SYM("@args"); s_binds = SYM("@binds"); s_body = SYM("@body");
  s_scrut = SYM("@scrut"); s_binder = SYM("@binder"); s_con_alts = SYM("@con_alts");
  s_lit_alts = SYM("@lit_alts"); s_default = SYM("@default"); s_con = SYM("@con"); s_meth = SYM("@meth");
  s_strict = SYM("@strict"); s_cps = SYM("@cps"); s_arity = SYM("@arity"); s_captures = SYM("@captures");
  s_nlocals = SYM("@nlocals"); s_tag = SYM("@tag"); s_nullary = SYM("@nullary"); s_top = SYM("@top");
  s_full = SYM("@full"); s_length = SYM("@length"); s_steps = SYM("@steps"); s_next_check = SYM("@next_check");
  s_stack = SYM("@stack"); s_fun = SYM("@fun"); s_payload = SYM("@payload");
  m_value = SYM("value");
  y_pending = SYM("pending"); y_value = SYM("value"); y_blackhole = SYM("blackhole"); y_raised = SYM("raised");
  y_thunk = SYM("thunk"); y_funk = SYM("fun"); y_conk = SYM("con"); y_str = SYM("str");
  p_integerAdd = SYM("p_integerAdd"); p_integerSub = SYM("p_integerSub"); p_integerMul = SYM("p_integerMul");
  p_integerEq = SYM("p_integerEq"); p_integerLt = SYM("p_integerLt"); p_integerLe = SYM("p_integerLe");
  p_integerGt = SYM("p_integerGt"); p_integerGe = SYM("p_integerGe"); p_intAdd = SYM("p_intAdd");
  p_intSub = SYM("p_intSub"); p_intMul = SYM("p_intMul"); p_charEq = SYM("p_charEq"); p_ord = SYM("p_ord");
  p_chr = SYM("p_chr");
  p_integerQuot = SYM("p_integerQuot"); p_integerRem = SYM("p_integerRem"); p_integerDiv = SYM("p_integerDiv");
  p_integerMod = SYM("p_integerMod"); p_intRem = SYM("p_intRem"); p_intMod = SYM("p_intMod");
  p_intToInteger = SYM("p_intToInteger"); p_integerToInt = SYM("p_integerToInt"); p_intNegate = SYM("p_intNegate");
  p_integerNegate = SYM("p_integerNegate"); p_doubleNegate = SYM("p_doubleNegate");
  p_doubleAdd = SYM("p_doubleAdd"); p_doubleSub = SYM("p_doubleSub"); p_doubleMul = SYM("p_doubleMul");
  p_doubleDiv = SYM("p_doubleDiv"); p_doubleEq = SYM("p_doubleEq"); p_doubleLt = SYM("p_doubleLt");
  p_doubleLe = SYM("p_doubleLe"); p_doubleGt = SYM("p_doubleGt"); p_doubleGe = SYM("p_doubleGe");

  struct RClass *rhci = mrb_define_module(mrb, "Rhci");
  struct RClass *vm = mrb_define_module_under(mrb, rhci, "VM");
  struct RClass *machine = mrb_define_class_under(mrb, vm, "Machine", mrb->object_class);
  mrb_define_method(mrb, machine, "run_native", machine_run_native, MRB_ARGS_REQ(4));
}

void
mrb_rhci_native_gem_final(mrb_state *mrb)
{
  rhci_term_final(mrb);
}
