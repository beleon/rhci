/*
 * Integer comparisons for bignums. mruby 4.0.0's int_equal (src/numeric.c)
 * also serves bignums but reads the receiver with mrb_integer(), which
 * truncates it: `2**64 + 7 == 7` and `(2**64).zero?` are true there, while
 * `7 == 2**64 + 7` is false. And mrb_bint_cmp's bignum-fixnum path is wrong
 * for a bignum holding INT64_MIN (what `-(2**63)` makes): it orders it below
 * the fixnum INT64_MIN. These replace ==, <=>, <, <=, > and >= on Integer:
 * a bignum and an integer are compared as two bignums; everything else as
 * mruby does.
 */

#include <mruby.h>
#include <mruby/internal.h>

/* -2, 0, 1 as mrb_bint_cmp; 2 when y is not a number (or x, y involve NaN). */
static mrb_int
cmp(mrb_state *mrb, mrb_value x, mrb_value y)
{
#ifndef MRB_NO_FLOAT
  if (mrb_float_p(y)) {
    mrb_float f = mrb_float(y);
    if (f != f) return 2;
#ifdef MRB_USE_BIGINT
    if (mrb_bigint_p(x)) return mrb_bint_cmp(mrb, x, y);
#endif
    mrb_float v = (mrb_float)mrb_integer(x);
    return v == f ? 0 : (v < f ? -1 : 1);
  }
#endif
#ifdef MRB_USE_BIGINT
  if (mrb_bigint_p(x) || mrb_bigint_p(y)) {
    if (!mrb_integer_p(y) && !mrb_bigint_p(y)) return 2;
    if (mrb_integer_p(x)) x = mrb_bint_new_int(mrb, mrb_integer(x));
    if (mrb_integer_p(y)) y = mrb_bint_new_int(mrb, mrb_integer(y));
    return mrb_bint_cmp(mrb, x, y);
  }
#endif
  if (!mrb_integer_p(y)) return 2;
  mrb_int a = mrb_integer(x), b = mrb_integer(y);
  return a == b ? 0 : (a < b ? -1 : 1);
}

static mrb_value
rhci_int_equal(mrb_state *mrb, mrb_value x)
{
  return mrb_bool_value(cmp(mrb, x, mrb_get_arg1(mrb)) == 0);
}

static mrb_value
rhci_int_cmp(mrb_state *mrb, mrb_value x)
{
  mrb_int c = cmp(mrb, x, mrb_get_arg1(mrb));
  return c == 2 ? mrb_nil_value() : mrb_fixnum_value(c);
}

static mrb_int
ordered(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
  mrb_int c = cmp(mrb, x, y);
  if (c == 2 && !mrb_float_p(y)) mrb_raise(mrb, E_ARGUMENT_ERROR, "comparison of Integer failed");
  return c;
}

static mrb_value rhci_int_lt(mrb_state *mrb, mrb_value x) { mrb_int c = ordered(mrb, x); return mrb_bool_value(c == -1); }
static mrb_value rhci_int_le(mrb_state *mrb, mrb_value x) { mrb_int c = ordered(mrb, x); return mrb_bool_value(c == -1 || c == 0); }
static mrb_value rhci_int_gt(mrb_state *mrb, mrb_value x) { mrb_int c = ordered(mrb, x); return mrb_bool_value(c == 1); }
static mrb_value rhci_int_ge(mrb_state *mrb, mrb_value x) { mrb_int c = ordered(mrb, x); return mrb_bool_value(c == 1 || c == 0); }

void
rhci_bigint_eq_init(mrb_state *mrb)
{
  struct RClass *i = mrb->integer_class;
  mrb_define_method(mrb, i, "==", rhci_int_equal, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, i, "<=>", rhci_int_cmp, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, i, "<", rhci_int_lt, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, i, "<=", rhci_int_le, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, i, ">", rhci_int_gt, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, i, ">=", rhci_int_ge, MRB_ARGS_REQ(1));
}
