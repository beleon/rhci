/* rhci entry point: the Ruby bundle is already loaded by mrb_open() (it is
 * this gem's mrblib, compiled to bytecode at build time), so startup never
 * parses Ruby source. All behaviour lives in Rhci::CLI.main. */
#include <stdio.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/string.h>

int
main(int argc, char **argv)
{
  mrb_state *mrb = mrb_open();
  if (mrb == NULL) {
    fputs("rhci: cannot initialise mruby\n", stderr);
    return 70;
  }
  if (mrb->exc) {               /* the bundle itself failed to load */
    mrb_print_error(mrb);
    mrb_close(mrb);
    return 70;
  }

  mrb_value args = mrb_ary_new_capa(mrb, argc > 1 ? argc - 1 : 0);
  for (int i = 1; i < argc; i++) {
    mrb_ary_push(mrb, args, mrb_str_new_cstr(mrb, argv[i]));
  }

  struct RClass *rhci = mrb_module_get(mrb, "Rhci");
  struct RClass *cli = mrb_module_get_under(mrb, rhci, "CLI");
  mrb_value status = mrb_funcall(mrb, mrb_obj_value(cli), "main", 1, args);

  int code = 70;                /* EX_SOFTWARE: an internal error escaped */
  if (mrb->exc) {
    mrb_print_error(mrb);
  }
  else if (mrb_integer_p(status)) {
    code = (int)mrb_integer(status);
  }
  mrb_close(mrb);
  return code;
}
