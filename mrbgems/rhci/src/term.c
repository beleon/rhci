/* Rhci::Term: the little of the terminal and process that the mruby REPL
 * needs and the lean mruby build lacks. lib/rhci/shim.rb is its only user;
 * CRuby gets the same from io/console, Signal.trap, ENV and Dir.
 *
 *   Term.tty?(fd)          isatty
 *   Term.raw(fd)           no echo, no line buffering, no signal keys;
 *                          output processing stays on. Saves the old mode.
 *   Term.restore(fd)       back to the saved mode
 *   Term.width(fd)         columns, or 80
 *   Term.read_byte(fd)     one byte: an Integer, nil at end of input, or
 *                          -1 if a signal interrupted the read
 *   Term.trap_sigint       SIGINT sets a flag instead of killing rhci;
 *                          reads are not restarted, so a blocked read
 *                          returns -1
 *   Term.take_sigint       true once per SIGINT received since last call
 *   Term.getenv(name)      a String or nil
 *   Term.entries(dir)      the names in a directory, or nil
 */
#include <dirent.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/string.h>

static volatile sig_atomic_t sigint_seen = 0;
static struct termios saved_mode;
static int saved_fd = -1;

static void
on_sigint(int sig)
{
  (void)sig;
  sigint_seen = 1;
}

static mrb_value
term_tty_p(mrb_state *mrb, mrb_value self)
{
  mrb_int fd;
  mrb_get_args(mrb, "i", &fd);
  return mrb_bool_value(isatty((int)fd) == 1);
}

static mrb_value
term_raw(mrb_state *mrb, mrb_value self)
{
  mrb_int fd;
  struct termios t;
  mrb_get_args(mrb, "i", &fd);
  if (tcgetattr((int)fd, &t) != 0) return mrb_false_value();
  if (saved_fd < 0) {
    saved_mode = t;
    saved_fd = (int)fd;
  }
  t.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  t.c_cflag |= CS8;
  t.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
  t.c_cc[VMIN] = 1;
  t.c_cc[VTIME] = 0;
  return mrb_bool_value(tcsetattr((int)fd, TCSADRAIN, &t) == 0);
}

static mrb_value
term_restore(mrb_state *mrb, mrb_value self)
{
  if (saved_fd >= 0) {
    tcsetattr(saved_fd, TCSADRAIN, &saved_mode);
    saved_fd = -1;
  }
  return mrb_nil_value();
}

static mrb_value
term_width(mrb_state *mrb, mrb_value self)
{
  mrb_int fd;
  struct winsize w;
  mrb_get_args(mrb, "i", &fd);
  if (ioctl((int)fd, TIOCGWINSZ, &w) == 0 && w.ws_col > 0) return mrb_int_value(mrb, w.ws_col);
  return mrb_int_value(mrb, 80);
}

static mrb_value
term_read_byte(mrb_state *mrb, mrb_value self)
{
  mrb_int fd;
  unsigned char b;
  mrb_get_args(mrb, "i", &fd);
  for (;;) {
    ssize_t n = read((int)fd, &b, 1);
    if (n == 1) return mrb_int_value(mrb, b);
    if (n == 0) return mrb_nil_value();
    if (errno == EINTR) {
      if (sigint_seen) return mrb_int_value(mrb, -1);
      continue;
    }
    return mrb_nil_value();
  }
}

static mrb_value
term_trap_sigint(mrb_state *mrb, mrb_value self)
{
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = on_sigint;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;              /* no SA_RESTART: a blocked read returns */
  sigaction(SIGINT, &sa, NULL);
  return mrb_nil_value();
}

static mrb_value
term_take_sigint(mrb_state *mrb, mrb_value self)
{
  if (!sigint_seen) return mrb_false_value();
  sigint_seen = 0;
  return mrb_true_value();
}

static mrb_value
term_getenv(mrb_state *mrb, mrb_value self)
{
  char *name;
  mrb_get_args(mrb, "z", &name);
  const char *v = getenv(name);
  return v ? mrb_str_new_cstr(mrb, v) : mrb_nil_value();
}

static mrb_value
term_entries(mrb_state *mrb, mrb_value self)
{
  char *path;
  mrb_get_args(mrb, "z", &path);
  DIR *d = opendir(path);
  if (d == NULL) return mrb_nil_value();
  mrb_value out = mrb_ary_new(mrb);
  int ai = mrb_gc_arena_save(mrb);
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
    mrb_ary_push(mrb, out, mrb_str_new_cstr(mrb, e->d_name));
    mrb_gc_arena_restore(mrb, ai);
  }
  closedir(d);
  return out;
}

void
mrb_rhci_gem_init(mrb_state *mrb)
{
  struct RClass *rhci = mrb_define_module(mrb, "Rhci");
  struct RClass *term = mrb_define_module_under(mrb, rhci, "Term");
  mrb_define_module_function(mrb, term, "tty?", term_tty_p, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, term, "raw", term_raw, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, term, "restore", term_restore, MRB_ARGS_NONE());
  mrb_define_module_function(mrb, term, "width", term_width, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, term, "read_byte", term_read_byte, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, term, "trap_sigint", term_trap_sigint, MRB_ARGS_NONE());
  mrb_define_module_function(mrb, term, "take_sigint", term_take_sigint, MRB_ARGS_NONE());
  mrb_define_module_function(mrb, term, "getenv", term_getenv, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, term, "entries", term_entries, MRB_ARGS_REQ(1));
}

void
mrb_rhci_gem_final(mrb_state *mrb)
{
  (void)mrb;
  if (saved_fd >= 0) tcsetattr(saved_fd, TCSADRAIN, &saved_mode);
}
