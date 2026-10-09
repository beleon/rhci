# frozen_string_literal: true

module Rhci
  # Outcome of one input. `status` is one of:
  #   :ok, :parse_error, :scope_error, :compile_error, :exception,
  #   :unsupported, :limit, :command_error
  class Result
    attr_reader :status, :message

    def initialize(status, message = nil)
      @status = status
      @message = message
    end

    def ok?
      @status == :ok
    end
  end

  # One independent interpreter state: the embedding API. Output produced by
  # Haskell code goes to `stdout`; nothing is written anywhere else.
  #
  # Every input runs the whole pipeline -- parse, rename, type-check,
  # desugar, lower, run -- and the session's names, types and globals are
  # only updated once an input has checked completely.
  class Session
    # GHCi commands, in the order GHCi resolves abbreviations (`:t` is
    # `:type`). :quit is the CLI's business.
    COMMANDS = %w[? help load quit reload type].freeze

    # prelude: :source (compile prelude/Prelude.hs), :snapshot (decode the
    # build-time snapshot), or :auto (the snapshot when this runtime has one
    # embedded, as the mruby binary does).
    # cwd: the directory :load resolves relative paths and module names in
    # (default: the process's working directory).
    def initialize(stdout: nil, stdin: nil, stderr: nil, limits: nil, prelude: :auto, cwd: nil)
      @prelude_mode = prelude
      @cwd = cwd
      @stdout = stdout
      @stdin = stdin
      @stderr = stderr
      @limits = limits
      @names = NameEnv.new
      @tenv = {}
      @globals = {}
      # Simplified Core of small global functions and constants, for
      # inlining across definitions (name => VM::Cell holding Core); the
      # Core of dictionary-abstracted functions, for specialisation; and the
      # specialisations made so far (key => global name).
      @unfoldings = {}
      @full_cores = {}
      @specs = {}
      @fixities = {}
      @machine = VM::Machine.new(stdout, limits, input: stdin, err: stderr)
      @prelude_loaded = false
    end

    # The full command name an abbreviation stands for, or nil.
    def self.command_name(word)
      return nil if word.empty?

      COMMANDS.find { |c| c.start_with?(word) }
    end

    def interrupt!
      @machine.interrupt!
    end

    # The next line of stdin for the REPL's own reader, which shares stdin
    # with Haskell code (getLine, isEOF) as GHCi's does. nil at its end,
    # :interrupt if Ctrl-C ended the read.
    def read_line
      pre = @machine.take_peeked
      return pre if pre == "\n"

      rest = Shim.read_line(@stdin)
      return rest if rest == :interrupt
      return pre if rest.nil?

      pre ? pre + rest : rest
    end

    # Characters a Ctrl-C-free Haskell read left in the machine's look-ahead
    # (isEOF): the line editor must see them first.
    def pending_input
      @machine.take_peeked
    end

    # Evaluate one GHCi input (expression, declarations, `let`, command).
    def eval(input)
      @machine.begin_evaluation
      return command(input) if Rhci::Text.lstrip(input).start_with?(':')

      node, layer = Frontend.parse_repl(input, @fixities)
      return Result.new(:ok) if node.is_a?(AST::ReplEmpty)

      begin
        eval_node(node, layer)
      rescue UnsupportedError => e
        remember_refused(node, e)
        raise e
      end
    rescue Error => e
      failure(e)
    rescue VM::HsException => e
      @machine.flush_output
      Result.new(:exception, @machine.exception_message(e))
    rescue VM::LimitExceeded => e
      @machine.flush_output
      Result.new(:limit, e.message)
    end

    def eval_node(node, layer)
      load_prelude
      case node
      when AST::ReplExpr then eval_expression(node.expr, layer)
      when AST::ReplBind then eval_bind(node, layer)
      else
        rtop = Renamer.new(@names, fixity: fixity_lookup).repl(node)
        return Result.new(:ok) if rtop.import

        tc = TypeChecker.new(@names, @tenv)
        tc.top(rtop)
        defs, = Desugar.new(@names).top(rtop)
        commit(rtop, tc, defs, layer)
        Result.new(:ok)
      end
    end

    # GHCi: `let it = e`, then `print it` -- or, when it is an IO action, run
    # it and print its result (unless that is (), or has no Show instance).
    def eval_expression(expr, layer, raw_strings: false, arity_args: nil, want: nil, internal: false)
      # `let it = e` is not recursive: `it` inside e is the previous one. So
      # the binding gets an internal name and becomes `it` once committed.
      @it_count = (@it_count || 0) + 1
      name_it = "rhci_it#{@it_count}"
      it_decl = AST::FunEq.new(expr.tok, name_it, [], AST::Rhs.new(expr.tok, expr, nil, nil))
      rtop = Renamer.new(@names, fixity: fixity_lookup, internal: internal)
                    .repl(AST::ReplDecls.new(expr.tok, [it_decl]))
      tc = TypeChecker.new(@names, @tenv)
      tc.top(rtop)
      it_name = rtop.values[name_it]
      plan = tc.print_plan(it_name, expr.tok)
      value_type = plan[:node].ty
      check_command_mode(plan, value_type, arity_args, want) if want
      defs, = Desugar.new(@names).top(rtop)
      ds = Desugar.new(@names)
      it_core = ds.expression(plan[:node])
      commit(rtop, tc, defs, layer)
      @names.values['it'] = it_name
      @names.refused.delete('it')
      if plan[:io]
        value = run_io_value(eval_core(it_core))
        result_type = Types.spine(value_type)[1][0]
        bind_it(value, result_type) unless unit_type?(result_type)
        print_value(ds, plan[:show], value_cell(value), result_type, raw_strings) if plan[:show]
      else
        print_value(ds, plan[:show], it_core, value_type, raw_strings)
      end
      Result.new(:ok)
    end

    def check_command_mode(plan, t, arity_args, want)
      if want == :pure
        if plan[:io]
          raise Error.new(:compile, 'the expression is an IO action; use rhci -x to run it')
        end
        if Types.split_fn(t)
          raise Error.new(:compile, "the function expects more arguments than the #{arity_args} given")
        end
      elsif !plan[:io]
        raise Error.new(:compile, 'the expression is not an IO action; use rhci -c to evaluate it')
      end
    end

    # Write show v (or a String raw) followed by a newline, as it is produced.
    def print_value(ds, show_ev, core, type, raw_strings)
      if raw_strings && string_type?(type)
        write_string(eval_core(core))
        return
      end
      raise Error.new(:compile, 'no Show instance') unless show_ev

      write_string(eval_core(ds.show_call(show_ev, core)))
      write_text("\n")
    end

    def value_cell(value)
      cell = VM::Cell.new("it%value%#{@globals.length}", value)
      @globals = @globals.merge(cell.name => cell)
      Core::Var.new(cell.name)
    end

    # After an IO statement, `it` is its result.
    def bind_it(value, type)
      name = @names.fresh('it', :var)
      name.global = true
      cell = VM::Cell.new(name.core, value)
      @globals = @globals.merge(cell.name => cell)
      @names.values['it'] = name
      @tenv[name] = Types.mono(type)
    end

    # pat <- action
    def eval_bind(node, layer)
      rtop = Renamer.new(@names, fixity: fixity_lookup).repl(node)
      tc = TypeChecker.new(@names, @tenv)
      tc.top(rtop)
      defs, core = Desugar.new(@names).top(rtop)
      commit(rtop, tc, defs, layer)
      value = run_io_value(eval_core(core))
      cell = value_cell(value)
      ds = Desugar.new(@names)
      fail = Core::Prim.new(:raise, [value_cell(@machine.haskell_string('Irrefutable pattern failed'))])
      bind_defs = rtop.values.values.map do |n|
        [n.core, ds.match_value(cell.name, node.pat, Core::Var.new(n.core), fail)]
      end
      install(bind_defs)
      Result.new(:ok)
    end

    # `rhci -c EXPR ARG...`: apply a pure EXPR to ARGs, each a Haskell
    # expression; a String result is written raw, anything else with show.
    def run_pure(expr, args, interact: false)
      e = command_expression(expr, args, interact)
      load_prelude
      @machine.semi_close_stdin if interact
      eval_expression(e, nil, raw_strings: true, arity_args: args.length + (interact ? 1 : 0), want: :pure,
                              internal: interact)
    rescue Error => e
      failure(e)
    rescue VM::HsException => e
      @machine.flush_output
      Result.new(:exception, @machine.exception_message(e))
    rescue VM::LimitExceeded => e
      @machine.flush_output
      Result.new(:limit, e.message)
    end

    # `rhci -x EXPR ARG...`: run an IO EXPR; ARGs are visible via getArgs.
    def run_io(expr, args, interact: false)
      @machine.args = args
      e = command_expression(expr, [], interact)
      load_prelude
      @machine.semi_close_stdin if interact
      eval_expression(e, nil, raw_strings: true, want: :io, internal: interact)
    rescue Error => e
      failure(e)
    rescue VM::HsException => e
      @machine.flush_output
      Result.new(:exception, @machine.exception_message(e))
    rescue VM::LimitExceeded => e
      @machine.flush_output
      Result.new(:limit, e.message)
    end

    # EXPR applied to ARGs (each a Haskell expression) and, with -i, to
    # stdin as a lazy String.
    def command_expression(expr, args, interact = false)
      e = Frontend.parse_expression(expr, @fixities)
      arg_nodes = args.map { |a| AST::Paren.new(nil, Frontend.parse_expression(a, @fixities)) }
      arg_nodes << AST::Var.new(e.tok, 'rhci_stdinContents') if interact
      return e if arg_nodes.empty?

      AST::App.new(e.tok, AST::Paren.new(e.tok, e), arg_nodes)
    end

    # `:load PATH...` / `rhci PATH...`: replace the loaded modules, as
    # GHCi does: prompt bindings are discarded; on success the scope is the
    # (last) module's full scope; on failure only the Prelude remains.
    def load(paths)
      load_prelude
      reset_to_baseline
      @last_load = paths
      if paths.empty?
        write_text("Ok, no modules loaded.\n")
        return Result.new(:ok)
      end
      @modules = {}
      @loading = []
      top = nil
      paths.each { |p| top = load_module_file(resolve_load_target(p), nil) }
      expose_module_scope(top)
      n = @modules.length
      write_text("Ok, #{n == 1 ? 'one module' : "#{n} modules"} loaded.\n")
      Result.new(:ok)
    rescue Error => e
      reset_to_baseline
      r = failure(e)
      Result.new(r.status, "#{r.message}\nFailed, no modules loaded.")
    rescue VM::HsException => e
      reset_to_baseline
      Result.new(:exception, @machine.exception_message(e))
    end

    def reload
      return load(@last_load) if @last_load

      write_text("Ok, no modules loaded.\n")
      Result.new(:ok)
    end

    # Tab completion for the text before the cursor: [start, candidates],
    # where start is the index the completed word begins at. Commands after
    # a leading ':', file names after :load, else names in scope.
    def completions(before)
      start = before.length
      start -= 1 while start.positive? && completion_char?(before[start - 1])
      word = before[start..-1]
      lead = Text.lstrip(before)
      if lead.start_with?(':')
        cmd_end = lead.index(' ')
        if cmd_end.nil?
          return [start, (COMMANDS + %w[quit]).uniq.select { |c| c.start_with?(word) && c != '?' }.sort]
        end
        return file_completions(before) if %w[load reload].include?(Session.command_name(lead[1...cmd_end]))
      end
      return [start, []] if word.empty? || !AST.ident_start?(word[0])

      load_prelude
      found = {}
      @names.values.each_key { |n| found[n] = true if n.start_with?(word) && !n.start_with?('rhci_') }
      @names.types.each_key { |n| found[n] = true if n.start_with?(word) }
      [start, found.keys.sort]
    end

    # The type of an expression, as :type prints it.
    def type_of(src)
      e = Frontend.parse_expression(src, @fixities)
      load_prelude
      Renamer.new(@names).expression(e)
      s = TypeChecker.new(@names, @tenv).expression_scheme(e)
      "#{src} :: #{Types::Printer.new.scheme(s)}"
    end

    private

    # ---- modules -------------------------------------------------------------------

    # What the session looks like with only the Prelude: restored by :load.
    def capture_baseline
      classes = []
      @names.types.each_value { |n| classes << n.klass if n.kind == :class }
      @baseline = {
        values: @names.values.dup, types: @names.types.dup,
        instances: classes.map { |ci| [ci, ci.instances.dup] }
      }
    end

    def reset_to_baseline
      @names.values.replace(@baseline[:values].dup)
      @names.types.replace(@baseline[:types].dup)
      @baseline[:instances].each { |ci, inst| ci.instances.replace(inst.dup) }
      @names.refused.clear
      @fixities = {}
    end

    # A :load argument: a file path (with or without .hs), or a module name.
    def resolve_load_target(arg)
      [arg, "#{arg}.hs", module_path(arg)].each do |p|
        return p if p && Shim.read_file(in_cwd(p))
      end
      raise Error.new(:compile, "can't find file: #{arg}", nil, nil, '<no location info>')
    end

    def module_path(name)
      return nil unless name[0] >= 'A' && name[0] <= 'Z'

      "#{name.split('.').join('/')}.hs"
    end

    def in_cwd(path)
      @cwd && !path.start_with?('/') ? "#{@cwd}/#{path}" : path
    end

    def load_module_file(path, expected)
      src = Shim.read_file(in_cwd(path))
      raw = Frontend.parse_module_raw(src, path)
      name = raw.name
      if expected && name != expected
        raise Error.new(:compile, "File name does not match module name: saw ‘#{name}’, expected ‘#{expected}’",
                        nil, nil, path)
      end
      return @modules[name] if @modules.key?(name)
      if @loading.include?(name)
        raise Error.new(:compile, "Module graph contains a cycle: #{(@loading + [name]).join(' imports ')}",
                        nil, nil, path)
      end

      @loading.push(name)
      imported = { values: {}, types: {} }
      official = []
      hidden = []
      fixities = {}
      local = []
      raw.imports.each do |imp|
        if Renamer::KNOWN_MODULES.key?(imp.module_name)
          base_import(imp, official, hidden)
          next
        end
        target = module_path(imp.module_name)
        unless target && Shim.read_file(in_cwd(target))
          raise Error.new(:scope, "Could not find module ‘#{imp.module_name}’", imp.tok.line, imp.tok.col, path)
        end
        mod = load_module_file(target, imp.module_name)
        local << imp.module_name
        add_imports(imported, mod, imp, path)
        fixities.merge!(mod[:fixities])
      end
      m = Frontend.resolve_module(raw, fixities, path)
      renamer = Renamer.new(@names, path, fixity: fixity_lookup, imported: imported, module_mode: true,
                                          official: official, hidden: hidden)
      renamer.imported_modules = local
      rtop = renamer.module_decls(m)
      tc = TypeChecker.new(@names, @tenv, path, mode: :file)
      tc.top(rtop)
      defs, = Desugar.new(@names, path).top(rtop)
      install(defs)
      tc.pending.each { |n, sc| @tenv[n] = sc if n.global || n.kind != :var }
      tc.new_instances.each { |(klass, key), inst| klass.instances[key] = inst }
      layer = FixityResolver.new(fixities, path).group_layer(m.decls)
      mod = { name: name, rtop: rtop, imported: imported, fixities: fixities.merge(layer) }
      mod[:exports] = module_exports(m, rtop, imported, path)
      @modules[name] = mod
      @loading.pop
      mod
    end

    # import Prelude hiding (..) / import Data.List (sortOn): base modules.
    def base_import(imp, official, hidden)
      raise UnsupportedError, 'qualified imports are not supported yet' if imp.qualified || imp.as

      official << imp.module_name
      return unless imp.hiding && imp.items

      imp.items.each do |n, subs|
        hidden << n
        hidden.concat(subs) if subs.is_a?(Array)
      end
    end

    def add_imports(imported, mod, imp, path)
      raise UnsupportedError, 'qualified imports are not supported yet' if imp.qualified || imp.as

      exports = mod[:exports]
      wanted = nil
      if imp.items
        wanted = {}
        imp.items.each do |n, subs|
          wanted[n] = true
          if subs == :all
            (exports[:subs][n] || []).each { |x| wanted[x] = true }
          elsif subs
            subs.each { |x| wanted[x] = true }
          end
        end
      end
      exports[:values].each do |str, n|
        visible = wanted.nil? || (imp.hiding ? !wanted.key?(str) : wanted.key?(str))
        add_import(imported[:values], str, n) if visible
      end
      exports[:types].each do |str, n|
        visible = wanted.nil? || (imp.hiding ? !wanted.key?(str) : wanted.key?(str))
        imported[:types][str] = n if visible
      end
    end

    def add_import(table, str, n)
      old = table[str]
      if old.nil? || old.equal?(n)
        table[str] = n
      else
        list = old.is_a?(Array) ? old : [old]
        table[str] = list.include?(n) ? list : list + [n]
      end
    end

    # A module's exports: {values:, types:, subs: type => [constructor and
    # field names]}. No export list exports every top-level name.
    def module_exports(m, rtop, imported, path)
      subs = {}
      rtop.tyinfos.each { |ti| subs[ti.name.str] = ti.cons.flat_map { |c| [c.str] + (c.fields || []).map(&:str) } }
      rtop.classes.each { |ci| subs[ci.name.str] = ci.methods.map(&:str) }
      return { values: rtop.values.dup, types: rtop.types.dup, subs: subs } unless m.exports

      values = {}
      types = {}
      own_values = rtop.values
      m.exports.each do |item, what|
        if item == :module
          src = what == m.name ? { values: own_values, types: rtop.types } : imported
          src[:values].each { |k, v| values[k] = v }
          src[:types].each { |k, v| types[k] = v }
          next
        end
        t = rtop.types[item] || imported[:types][item]
        if t
          types[item] = t
          names = what == :all ? (subs[item] || []) : (what || [])
          names.each do |x|
            v = own_values[x] || imported[:values][x]
            raise Error.new(:scope, "Not in scope: ‘#{x}’ in the export list", nil, nil, path) unless v

            values[x] = v
          end
        else
          v = own_values[item] || imported[:values][item]
          raise Error.new(:scope, "Not in scope: ‘#{item}’ in the export list", nil, nil, path) unless v

          values[item] = v
        end
      end
      { values: values, types: types, subs: subs }
    end

    # After a load the prompt sees the module's full scope (GHCi's *M).
    def expose_module_scope(mod)
      mod[:imported][:values].each { |s, n| @names.values[s] = n unless n.is_a?(Array) }
      mod[:imported][:types].each { |s, n| @names.types[s] = n }
      mod[:rtop].values.each { |s, n| @names.values[s] = n unless s.start_with?('rhci_') }
      mod[:rtop].types.each { |s, n| @names.types[s] = n }
      @fixities = mod[:fixities].dup
    end

    # The build-time snapshot text, if this runtime has one embedded.
    # Lets a host (or a test) supply snapshot text explicitly.
    def self.snapshot_text=(text)
      @embedded_snapshot = text
    end

    def self.embedded_snapshot
      return @embedded_snapshot if @embedded_snapshot
      return PRELUDE_SNAPSHOT if Rhci.const_defined?(:PRELUDE_SNAPSHOT)
      return nil unless Rhci.const_defined?(:PRELUDE_SNAPSHOT_PARTS)

      @embedded_snapshot ||= PRELUDE_SNAPSHOT_PARTS.join
    end

    # What the snapshot captures after the Prelude has loaded.
    def prelude_state
      [@names, @tenv, @globals, @unfoldings, @full_cores, @specs]
    end

    def fixity_lookup
      table = @fixities
      ->(op) { table[op] || FixityResolver::BASE[op] || FixityResolver::DEFAULT }
    end

    # ---- the Prelude -----------------------------------------------------------

    def load_prelude
      return if @prelude_loaded

      @prelude_loaded = true
      snapshot = Session.embedded_snapshot
      if @prelude_mode == :snapshot || (@prelude_mode == :auto && snapshot)
        raise 'no Prelude snapshot is available' unless snapshot

        @names, @tenv, @globals, @unfoldings, @full_cores, @specs = Snapshot.decode(snapshot)
        capture_baseline
        return
      end
      m = Frontend.parse_module(PRELUDE_SOURCE, '<Prelude>', prelude: true)
      rtop = Renamer.new(@names, '<Prelude>', prelude: true).module_decls(m)
      tc = TypeChecker.new(@names, @tenv, '<Prelude>')
      tc.top(rtop)
      defs, = Desugar.new(@names, '<Prelude>').top(rtop)
      commit(rtop, tc, defs, nil, prelude: true)
      capture_baseline
    rescue StandardError => e
      @prelude_loaded = false
      raise "rhci: the Prelude failed to load: #{e.message}"
    end

    # ---- committing and running --------------------------------------------------

    def commit(rtop, tc, defs, layer, prelude: false)
      install(defs)
      @names.commit(rtop, prelude: prelude)
      tc.pending.each { |n, s| @tenv[n] = s if n.global || n.kind != :var }
      tc.new_instances.each { |(klass, key), inst| klass.instances[key] = inst }
      layer&.each { |k, v| @fixities[k] = v }
    end

    def install(defs)
      cells = defs.map { |name, _| VM::Cell.new(name) }
      cells.each { |c| @globals[c.name] = c }
      values = defs.map { |name, core| compile_global(name, core) }
      cells.each_with_index { |c, i| c.value = values[i] }
    end

    # Simplified, recorded for inlining and specialisation, and lowered.
    def compile_global(name, core)
      core = lift_fields(name, simplifier.run(core))
      u = Simplify.unfolding(name, core)
      @unfoldings[name] = VM::Cell.new(name, u) if u
      if core.is_a?(Core::Lam) && core.params[0].to_s.start_with?('dict%')
        @full_cores[name] = VM::Cell.new(name, core)
      end
      Lower.new(@globals).global_value(name, core)
    end

    # A top-level constructor application (a dictionary, mostly) with
    # non-atomic fields gets each such field as a global of its own, so the
    # value is a constant the simplifier can see through.
    def lift_fields(name, core)
      return core unless core.is_a?(Core::Con)

      args = []
      core.args.each do |a|
        if a.is_a?(Core::Var) || a.is_a?(Core::Lit)
          args << a
          next
        end
        field = "#{name}$#{args.length}"
        cell = VM::Cell.new(field)
        @globals[field] = cell
        cell.value = compile_global(field, a)
        args << Core::Var.new(field)
      end
      Core::Con.new(core.con, args)
    end

    def simplifier
      Simplify.new(@unfoldings, ->(name, dicts) { specialize(name, dicts) })
    end

    SPEC_LIMIT = 5000

    # The global specialising `name` to the dictionaries `dicts` (closed
    # Core), made on first request; nil if `name` cannot be specialised.
    def specialize(name, dicts)
      key = "#{name}@#{dicts.map { |d| Simplify.key(d) }.join(',')}"
      return @specs[key] if @specs.key?(key)

      full = @full_cores[name]&.value
      return nil unless full.is_a?(Core::Lam) && @specs.length < SPEC_LIMIT

      n = dicts.length
      n = full.params.length if n > full.params.length
      binds = []
      n.times { |i| binds << [full.params[i], dicts[i]] }
      body = n < full.params.length ? Core::Lam.new(full.params[n..-1], full.body) : full.body
      @specs[key] = key
      cell = VM::Cell.new(key)
      @globals[key] = cell
      cell.value = compile_global(key, Core::Let.new(binds, body))
      key
    end

    def eval_core(core)
      code = Lower.new(@globals).expression(simplifier.run(core))
      @machine.eval_code(code)
    end

    # A String result, written as it is produced.
    def write_string(v)
      cell = @machine.whnf(v)
      while cell[0].equal?(VM::Builtins::CONS)
        c = @machine.whnf(cell[1])
        write_text(''.dup << c)
        cell = @machine.whnf(cell[2])
      end
      @machine.flush_output
    end

    def write_text(s)
      Shim.write(@stdout, s) if @stdout
    end

    # Apply the action to the world token and force its IORes.
    def run_io_value(io)
      res = @machine.apply(io, [VM::Builtins::UNIT_V])
      @machine.flush_output
      res[1]
    end

    def completion_char?(c)
      AST.ident_start?(c) || (c >= '0' && c <= '9') || c == "'" || c == '_'
    end

    # The path being typed after `:load `: entries of its directory.
    def file_completions(before)
      start = before.rindex(' ') + 1
      path = before[start..-1]
      slash = path.rindex('/')
      dir = slash ? path[0..slash] : ''
      base = slash ? path[(slash + 1)..-1] : path
      look = dir.empty? ? '.' : dir
      look = "#{@cwd}/#{look}" if @cwd && !look.start_with?('/')
      names = Shim.dir_entries(look) || []
      out = []
      names.each do |n|
        next unless n.start_with?(base)
        next if n.start_with?('.') && !base.start_with?('.')

        sub = Shim.dir_entries(look == '.' ? n : "#{look}/#{n}")
        out << "#{dir}#{n}#{sub ? '/' : ''}"
      end
      [start, out.sort]
    end

    # ---- types ---------------------------------------------------------------------

    def unit_type?(t)
      Types.prune(t).equal?(Types::UNIT)
    end

    def string_type?(t)
      h, args = Types.spine(t)
      h.equal?(Types::LIST) && Types.prune(args[0]).equal?(Types::CHAR)
    end

    # The names an input would have defined, so that their later uses are
    # reported as unsupported rather than not in scope.
    def remember_refused(node, err)
      why = err.detail
      names = []
      case node
      when AST::ReplExpr then names << 'it'
      when AST::ReplBind then collect_binders(node.pat, names)
      when AST::ReplLet, AST::ReplDecls
        node.decls.each do |d|
          case d
          when AST::FunEq then names << d.name
          when AST::PatBind then collect_binders(d.pat, names)
          when AST::DataDecl
            names << d.name
            d.cons.each do |c|
              names << c.name
              names.concat(c.field_names || [])
            end
          when AST::TypeSyn then names << d.name
          end
        end
      end
      names.each { |n| @names.refused[n] = why }
    end

    def collect_binders(p, acc)
      case p
      when AST::PVar then acc << p.name
      when AST::PAs
        acc << p.name
        collect_binders(p.pat, acc)
      when AST::PCon then p.args.each { |a| collect_binders(a, acc) }
      when AST::PTuple, AST::PList then p.elems.each { |a| collect_binders(a, acc) }
      when AST::PLazy, AST::PBang then collect_binders(p.pat, acc)
      when AST::PRec then p.fields.each { |_, a| collect_binders(a, acc) }
      when AST::POpSeq then p.items.each { |a| collect_binders(a, acc) }
      end
    end

    # ---- commands --------------------------------------------------------------------

    def command(input)
      text = Rhci::Text.lstrip(input)[1..-1]
      word, arg = split_word(text)
      case Session.command_name(word)
      when 'type'
        return Result.new(:command_error, 'not an expression: ‘’') if Rhci::Text.blank?(arg)

        # Positions are relative to the argument, as in GHCi.
        line = type_of(Rhci::Text.strip(arg))
        Shim.write(@stdout, "#{line}\n") if @stdout
        Result.new(:ok)
      when 'load' then load(Rhci::Text.strip(arg).split(' '))
      when 'reload' then reload
      when nil
        Result.new(:command_error, "unknown command ':#{word}'\nuse :? for help.")
      else
        Result.new(:unsupported, ":#{Session.command_name(word)} is not implemented yet")
      end
    rescue Error => e
      failure(e)
    end

    def split_word(text)
      i = 0
      i += 1 while i < text.length && text[i] != ' ' && text[i] != "\t" && text[i] != "\n"
      [text[0, i], text[i..-1] || '']
    end

    def failure(err)
      status = { parse: :parse_error, scope: :scope_error, compile: :compile_error,
                 unsupported: :unsupported }[err.kind] || :compile_error
      Result.new(status, err.message)
    end
  end
end
