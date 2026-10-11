/*
 * Integer arithmetic on bignums. mruby 4.0.0's mruby-bigint takes fast
 * paths when one operand is a fixnum, and several are wrong:
 *   +, -  bignum +/- a small fixnum: mpz_add_int sets the sign positive
 *         when the carry grows a limb (-18446744073709551614 + -9 is
 *         positive); a fixnum +/- a bignum swaps into the same path;
 *   &, ^  a negative bignum & a small positive fixnum ANDs the magnitude,
 *         and with two bignums a result that needs one more limb than
 *         either operand loses it (-2^96 & -(2^128 - 3) is 0);
 *   ~     of a positive bignum is -x + 1 (mpz_sub_int ignores the sign);
 *   >>    of a negative bignum truncates instead of flooring (and so does
 *         << with a negative width).
 * Addition and subtraction of two bignums are right, and so are the
 * bitwise operations on nonnegative ones. So whenever a bignum is involved
 * these widen both operands to bignums, reduce a bitwise operation on a
 * negative operand to nonnegative ones (~x = -x - 1 is nonnegative for a
 * negative x), and floor the shift themselves; every other case goes to
 * mruby's own method, saved at init.
 */

#include <mruby.h>
#include <mruby/class.h>
#include <mruby/proc.h>
#include <mruby/internal.h>

enum { OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_REV, OP_RSHIFT, OP_LSHIFT, OP_COUNT };
static mrb_func_t original[OP_COUNT];

static mrb_bool
integral(mrb_value v)
{
  return mrb_integer_p(v) || mrb_bigint_p(v);
}

static mrb_value
widen(mrb_state *mrb, mrb_value v)
{
  return mrb_integer_p(v) ? mrb_bint_new_int(mrb, mrb_integer(v)) : v;
}

/* Both integers and at least one a bignum. */
static mrb_bool
big_pair(mrb_value x, mrb_value y)
{
  return integral(x) && integral(y) && (mrb_bigint_p(x) || mrb_bigint_p(y));
}

static mrb_value
int_add(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  if (big_pair(x, y)) return mrb_bint_add(mrb, widen(mrb, x), widen(mrb, y));
  return original[OP_ADD](mrb, x);
}

static mrb_value
int_sub(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  if (big_pair(x, y)) return mrb_bint_sub(mrb, widen(mrb, x), widen(mrb, y));
  return original[OP_SUB](mrb, x);
}

static mrb_value
one(mrb_state *mrb)
{
  return mrb_bint_new_int(mrb, 1);
}

static mrb_bool
negative(mrb_state *mrb, mrb_value v)
{
  return mrb_integer_p(v) ? mrb_integer(v) < 0 : mrb_bint_sign(mrb, v) < 0;
}

static mrb_value
sub(mrb_state *mrb, mrb_value x, mrb_value y)
{
  return mrb_bint_sub(mrb, widen(mrb, x), widen(mrb, y));
}

/* ~x = -x - 1 */
static mrb_value
complement(mrb_state *mrb, mrb_value x)
{
  return sub(mrb, mrb_bint_neg(mrb, widen(mrb, x)), one(mrb));
}

enum { AND, OR, XOR };

/* x op y for nonnegative x and y. */
static mrb_value
bitop_nn(mrb_state *mrb, int op, mrb_value x, mrb_value y)
{
  x = widen(mrb, x);
  y = widen(mrb, y);
  return op == AND ? mrb_bint_and(mrb, x, y) : op == OR ? mrb_bint_or(mrb, x, y) : mrb_bint_xor(mrb, x, y);
}

/* With nx = ~x and ny = ~y (nonnegative where x, y are negative):
     x & y = ~(nx | ny),  x | y = ~(nx & ny),  x ^ y = nx ^ ny;
     x & p = p - (p & nx),  x | p = ~(nx - (nx & p)),  x ^ p = ~(nx ^ p). */
static mrb_value
bitop(mrb_state *mrb, int op, mrb_value x, mrb_value y)
{
  mrb_bool xn = negative(mrb, x), yn = negative(mrb, y);
  if (!xn && !yn) return bitop_nn(mrb, op, x, y);
  if (xn && yn) {
    mrb_value nx = complement(mrb, x), ny = complement(mrb, y);
    if (op == XOR) return bitop_nn(mrb, XOR, nx, ny);
    return complement(mrb, bitop_nn(mrb, op == AND ? OR : AND, nx, ny));
  }
  if (yn) { mrb_value t = x; x = y; y = t; } /* x negative, y nonnegative */
  mrb_value nx = complement(mrb, x);
  switch (op) {
  case AND: return sub(mrb, y, bitop_nn(mrb, AND, y, nx));
  case OR: return complement(mrb, sub(mrb, nx, bitop_nn(mrb, AND, nx, y)));
  default: return complement(mrb, bitop_nn(mrb, XOR, nx, y));
  }
}

static mrb_value
int_and(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  if (big_pair(x, y)) return bitop(mrb, AND, x, y);
  return original[OP_AND](mrb, x);
}

static mrb_value
int_or(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  if (big_pair(x, y)) return bitop(mrb, OR, x, y);
  return original[OP_OR](mrb, x);
}

static mrb_value
int_xor(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  if (big_pair(x, y)) return bitop(mrb, XOR, x, y);
  return original[OP_XOR](mrb, x);
}

static mrb_value
int_rev(mrb_state *mrb, mrb_value x)
{
  if (mrb_bigint_p(x)) return complement(mrb, x);
  return original[OP_REV](mrb, x);
}

/* floor(x / 2^w) for a bignum x and w >= 0: for x < 0, -((-x - 1) >> w) - 1,
   shifting a nonnegative number (which truncation floors). */
static mrb_value
floor_shift(mrb_state *mrb, mrb_value x, mrb_int w)
{
  if (mrb_bint_sign(mrb, x) >= 0) return mrb_bint_rshift(mrb, x, w);
  return complement(mrb, mrb_bint_rshift(mrb, widen(mrb, complement(mrb, x)), w));
}

static mrb_value
int_rshift(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  if (mrb_bigint_p(x) && mrb_integer_p(y) && mrb_integer(y) >= 0) return floor_shift(mrb, x, mrb_integer(y));
  return original[OP_RSHIFT](mrb, x);
}

static mrb_value
int_lshift(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  if (mrb_bigint_p(x) && mrb_integer_p(y) && mrb_integer(y) < 0 && mrb_integer(y) != MRB_INT_MIN) {
    return floor_shift(mrb, x, -mrb_integer(y));
  }
  return original[OP_LSHIFT](mrb, x);
}

static void
replace(mrb_state *mrb, int op, const char *name, mrb_func_t f, mrb_aspec aspec)
{
  struct RClass *i = mrb->integer_class;
  mrb_method_t m = mrb_method_search(mrb, i, mrb_intern_cstr(mrb, name));
  if (!MRB_METHOD_CFUNC_P(m)) mrb_raise(mrb, E_RUNTIME_ERROR, "rhci: Integer method is not a C function");
  original[op] = MRB_METHOD_CFUNC(m);
  mrb_define_method(mrb, i, name, f, aspec);
}

void
rhci_bigint_ops_init(mrb_state *mrb)
{
  replace(mrb, OP_ADD, "+", int_add, MRB_ARGS_REQ(1));
  replace(mrb, OP_SUB, "-", int_sub, MRB_ARGS_REQ(1));
  replace(mrb, OP_AND, "&", int_and, MRB_ARGS_REQ(1));
  replace(mrb, OP_OR, "|", int_or, MRB_ARGS_REQ(1));
  replace(mrb, OP_XOR, "^", int_xor, MRB_ARGS_REQ(1));
  replace(mrb, OP_REV, "~", int_rev, MRB_ARGS_NONE());
  replace(mrb, OP_RSHIFT, ">>", int_rshift, MRB_ARGS_REQ(1));
  replace(mrb, OP_LSHIFT, "<<", int_lshift, MRB_ARGS_REQ(1));
}
