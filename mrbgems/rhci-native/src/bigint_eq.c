/*
 * Integer#== for bignum receivers. mruby 4.0.0's int_equal (src/numeric.c)
 * also serves bignums but reads the receiver with mrb_integer(), which
 * truncates it: `2**64 + 7 == 7` and `(2**64).zero?` are true there, while
 * `7 == 2**64 + 7` is false. This replaces the method with one that compares
 * a bignum with an integer as two bignums (mrb_bint_cmp's bignum-fixnum path
 * is wrong for a bignum holding INT64_MIN, which `-9223372036854775808`
 * makes), and otherwise does what int_equal does.
 */

#include <mruby.h>
#include <mruby/internal.h>

static mrb_value
rhci_int_equal(mrb_state *mrb, mrb_value x)
{
  mrb_value y = mrb_get_arg1(mrb);
#ifdef MRB_USE_BIGINT
  if (mrb_bigint_p(x)) {
    if (mrb_integer_p(y)) y = mrb_bint_new_int(mrb, mrb_integer(y));
    if (mrb_bigint_p(y) || mrb_float_p(y)) return mrb_bool_value(mrb_bint_cmp(mrb, x, y) == 0);
    return mrb_false_value();
  }
#endif
  switch (mrb_type(y)) {
  case MRB_TT_INTEGER:
    return mrb_bool_value(mrb_integer(x) == mrb_integer(y));
#ifndef MRB_NO_FLOAT
  case MRB_TT_FLOAT:
    return mrb_bool_value((mrb_float)mrb_integer(x) == mrb_float(y));
#endif
#ifdef MRB_USE_BIGINT
  case MRB_TT_BIGINT:
    return mrb_bool_value(mrb_bint_cmp(mrb, y, mrb_bint_new_int(mrb, mrb_integer(x))) == 0);
#endif
  default:
    return mrb_false_value();
  }
}

void
rhci_bigint_eq_init(mrb_state *mrb)
{
  mrb_define_method(mrb, mrb->integer_class, "==", rhci_int_equal, MRB_ARGS_REQ(1));
}
