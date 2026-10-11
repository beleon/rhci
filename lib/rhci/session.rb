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
    COMMANDS = %w[? help info kind load quit reload type].freeze

    # prelude: :source (compile prelude/Prelude.hs), :snapshot (decode the
    # build-time snapshot), or :auto (the snapshot when this runtime has one
    # embedded, as the mruby binary does).
    # cwd: the directory :load and readFile/writeFile resolve relative paths
    # and module names in (default: the process's working directory).
    # files: false makes readFile/writeFile/appendFile fail.
    def initialize(stdout: nil, stdin: nil, stderr: nil, limits: nil, prelude: :auto, cwd: nil, files: true)
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
      @machine = VM::Machine.new(stdout, limits, input: stdin, err: stderr, cwd: cwd, files: files)
      @prelude_loaded = false
      @background_loading = false
      @trace_snapshot = false
      @spec_trace = []
    end

    # Snapshot entries not decoded at startup are loaded on demand, and, with
    # background loading on (the CLI's REPL), while inputs run: once an
    # input has run for as long as decoding the snapshot's core took, the
    # machine loads entries for that long, then runs that long again, and
    # so on until everything is loaded. See also load_while_idle.
    attr_writer :background_loading
    # Build time (tools/snapshot.rb): record which entries inputs look up.
    attr_writer :trace_snapshot

    def snapshot_trace
      (@decoder && @decoder.trace_log) || []
    end

    def snapshot_decoded
      (@decoder && @decoder.decoded) || []
    end

    # Specialisations made, as [global name, dictionaries (portable_dict)].
    def snapshot_specs
      @spec_trace
    end

    # Build time: make the specialisation of global name to dictionaries
    # (portable_dict form) now, if every name involved is a global here.
    def prepare_specialization(name, dicts)
      return nil unless @globals.key?(name) && dicts.all? { |d| known_dict?(d) }

      specialize(name, dicts.map { |d| Session.dict_core(d) })
    end

    def known_dict?(d)
      d.is_a?(String) ? @globals.key?(d) : known_dict?(d[0]) && d[1].all? { |a| known_dict?(a) }
    end

    # Snapshot table entries not yet loaded (see Decoder#pending_count),
    # and loaded since startup.
    def pending_entries
      @decoder ? @decoder.pending_count : 0
    end

    def loaded_entries
      @decoder ? @decoder.loaded_count : 0
    end

    # Are snapshot entries still to be loaded?
    def loading?
      !@prelude_loaded || (!@decoder.nil? && @decoder.pending?)
    end

    # The REPL's idle time, before input arrives: loads the Prelude, then
    # pending snapshot entries in steps of a few milliseconds, until
    # ready.call says input is waiting or everything is loaded.
    def load_while_idle(ready)
      return if ready.call

      load_prelude
      while @decoder
        now = Shim.now
        if @decoder.load_step(now && now + IDLE_STEP)
          @decoder = nil
          @machine.background = nil
          return
        end
        return if ready.call
      end
    rescue StandardError
      nil # a broken Prelude is reported by the input that needs it
    end

    # The full command name an abbreviation stands for, or nil.
    def self.command_name(word)
      return nil if word.empty?

      COMMANDS.find { |c| c.start_with?(word) }
    end

    def interrupt!
      @machine.interrupt!
    end

    IDLE_STEP = 0.002

    def start_background
      return unless @background_loading && @decoder && @preload_time && @decoder.pending?

      @window = Shim.now
      @machine.background = -> { background_tick }
    end

    # Called by the machine every few thousand steps.
    def background_tick
      now = Shim.now
      return if now - @window < @preload_time

      if @decoder.load_step(now + @preload_time)
        @decoder = nil
        @machine.background = nil
      end
      @window = Shim.now
    end

    # Machine steps taken so far (what the :steps limit counts).
    def steps
      @machine.steps
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
      start_background
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
        rtop = Renamer.new(@names, fixity: fixity_lookup(layer)).repl(node)
        return prompt_import(rtop.import) if rtop.import

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
      rtop = Renamer.new(@names, fixity: fixity_lookup(layer), internal: internal)
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
      # As in GHCi, `it` changes only if the statement completes: an
      # exception while running or printing leaves the previous one.
      prev_it = @names.values['it']
      prev_refused = @names.refused['it']
      @names.values['it'] = it_name
      @names.refused.delete('it')
      begin
        if plan[:io]
          value = run_io_value(eval_core(it_core))
          result_type = Types.spine(value_type)[1][0]
          bind_it(value, result_type) # () too: after `print x`, it is ()
          print_value(ds, plan[:show], value_cell(value), result_type, raw_strings) if plan[:show]
        else
          print_value(ds, plan[:show], it_core, value_type, raw_strings)
        end
      rescue VM::HsException, VM::LimitExceeded => e
        restore_it(prev_it, prev_refused)
        raise e
      end
      Result.new(:ok)
    end

    def restore_it(name, refused)
      if name
        @names.values['it'] = name
      else
        @names.values.delete('it')
      end
      @names.refused['it'] = refused if refused
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
      @globals[cell.name] = cell
      Core::Var.new(cell.name)
    end

    # After an IO statement, `it` is its result.
    def bind_it(value, type)
      name = @names.fresh('it', :var)
      name.global = true
      cell = VM::Cell.new(name.core, value)
      @globals[cell.name] = cell
      @names.values['it'] = name
      @tenv[name] = Types.mono(type)
    end

    # pat <- action
    def eval_bind(node, layer)
      rtop = Renamer.new(@names, fixity: fixity_lookup(layer)).repl(node)
      tc = TypeChecker.new(@names, @tenv)
      tc.top(rtop)
      defs, core = Desugar.new(@names).top(rtop)
      install(defs)
      value = run_io_value(eval_core(core))
      cell = value_cell(value)
      ds = Desugar.new(@names)
      # The pattern is matched now, as GHCi's `pat <- io` does: a failure
      # is a (MonadFail) IO error and binds nothing.
      tok = node.pat.tok
      msg = "user error (Pattern match failure in interactive GHCi command at <interactive>:#{tok&.line || 1}:#{tok&.col || 1})"
      fail_now = Core::Prim.new(:raise, [value_cell(@machine.haskell_string(msg))])
      eval_core(ds.match_value(cell.name, node.pat, Core::Con.new(VM::Builtins::UNIT, []), fail_now))
      fail = Core::Prim.new(:raise, [value_cell(@machine.haskell_string('Irrefutable pattern failed'))])
      bind_defs = rtop.values.values.map do |n|
        [n.core, ds.match_binding(cell.name, node.pat, n, fail)]
      end
      commit(rtop, tc, bind_defs, layer)
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
    # GHCi does: prompt bindings are discarded; the scope is the (last)
    # module's full scope; on failure, that of the last module that did
    # load (GHCi keeps them), or only the Prelude. quiet: no "Ok, ...
    # loaded." line (the one-shot modes, like runghc).
    def load(paths, quiet: false)
      load_prelude
      reset_to_baseline
      @last_load = paths
      if paths.empty?
        write_text("Ok, no modules loaded.\n") unless quiet
        return Result.new(:ok)
      end
      @modules = {}
      @loading = []
      top = nil
      paths.each { |p| top = load_module_file(resolve_load_target(p), nil) }
      expose_module_scope(top)
      n = @modules.length
      write_text("Ok, #{n == 1 ? 'one module' : "#{n} modules"} loaded.\n") unless quiet
      Result.new(:ok)
    rescue Error => e
      r = failure(e)
      @loading = []
      n = @modules ? @modules.length : 0
      if n.zero?
        reset_to_baseline
      else
        # What failed installed nothing; the modules before it stay.
        expose_module_scope(@modules.values.last)
      end
      loaded = n.zero? ? 'no modules' : n == 1 ? 'one module' : "#{n} modules"
      Result.new(r.status, "#{r.message}\nFailed, #{loaded} loaded.")
    rescue VM::HsException => e
      reset_to_baseline
      Result.new(:exception, @machine.exception_message(e))
    end

    # GHC reads a `#!` first line (a runghc script) as a comment: the line
    # stays, empty, so positions are unchanged.
    def self.without_shebang(src)
      return src unless src.start_with?('#!')

      nl = src.index("\n")
      nl ? src[nl..-1] : ''
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

    # What :load returns to: the Prelude's names, and its instances (the
    # session's own are logged as they are added, and undone).
    def capture_baseline
      @baseline = { values: @names.values.dup, types: @names.types.dup }
      @instance_log = []
    end

    def add_instance(klass, key, inst)
      @instance_log&.push([klass, key, klass.instances.key?(key), klass.instances[key]])
      klass.instances[key] = inst
    end

    def reset_to_baseline
      @names.values.replace(@baseline[:values].dup)
      @names.types.replace(@baseline[:types].dup)
      @instance_log.reverse_each do |klass, key, had, old|
        if had
          klass.instances[key] = old
        else
          klass.instances.delete(key)
        end
      end
      @instance_log.clear
      @names.refused.clear
      @names.clear_definitions
      @names.local_modules = nil
      @names.module_scope = nil
      @fixities = {}
      prompt_alias_fixities
    end

    # The prompt's imports survive :load; so do their operators' fixities.
    def prompt_alias_fixities
      @names.aliases.each do |a, mods|
        mods.each_key { |m| alias_fixities(a, m).each { |k, v| @fixities[k] = v } }
      end
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
      src = Session.without_shebang(src) if src
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
      scope = DefaultScope.new
      fixities = {}
      local = []
      # Qualified names: the Prelude is implicitly importable as Prelude.x.
      qualified = { 'Prelude' => [['Prelude', @names.module_table('Prelude')]] }
      raw.imports.each do |imp|
        if MODULE_EXPORTS.key?(imp.module_name) || @names.library_module?(imp.module_name)
          base_import(imp, scope, imported, qualified, fixities, path)
          next
        end
        target = module_path(imp.module_name)
        unless target && Shim.read_file(in_cwd(target))
          Rhci.module_not_found(imp.module_name, imp.tok.line, imp.tok.col, path)
        end
        mod = load_module_file(target, imp.module_name)
        local << imp.module_name
        add_qualified(qualified, imp.as || imp.module_name, imp.module_name, mod[:exports])
        add_imports(imported, mod, imp, path) unless imp.qualified
        fixities.merge!(mod[:fixities])
      end
      m = Frontend.resolve_module(raw, fixities, path)
      layer = FixityResolver.new(fixities, path).group_layer(m.decls)
      renamer = Renamer.new(@names, path, fixity: fixity_lookup(fixities.merge(layer), prompt: false), imported: imported,
                                          module_mode: true, scope: scope, qualified: qualified)
      renamer.imported_modules = local
      rtop = renamer.module_decls(m)
      tc = TypeChecker.new(@names, @tenv, path, mode: :file)
      tc.top(rtop)
      defs, = Desugar.new(@names, path).top(rtop)
      install(defs)
      tc.pending.each { |n, sc| @tenv[n] = sc if n.global || n.kind != :var }
      tc.new_instances.each { |(klass, key), inst| add_instance(klass, key, inst) }
      mod = { name: name, rtop: rtop, imported: imported, scope: scope, fixities: fixities.merge(layer) }
      mod[:exports] = module_exports(m, rtop, imported, path)
      @modules[name] = mod
      @loading.pop
      mod
    end

    # A file's import of a base module: default-scope modules go into its
    # DefaultScope, others add their names; every import is a qualifier.
    def base_import(imp, scope, imported, qualified, fixities, path)
      mod = imp.module_name
      table = @names.module_table(mod)
      selection = import_selection(table, imp, path)
      add_qualified(qualified, imp.as || mod, mod, imp.items ? selection : table)
      alias_fixities(imp.as || mod, mod).each { |k, v| fixities[k] = v }
      return scope.import(mod, imp.qualified, selection, hidden_by(imp, table, selection)) if DEFAULT_MODULES.include?(mod)
      return if imp.qualified

      selection[:values].each { |str, n| add_import(imported[:values], str, n) }
      selection[:types].each { |str, n| imported[:types][str] = n }
    end

    # Several imports of one module under one alias add up.
    def add_qualified(qualified, alias_name, mod, table)
      list = (qualified[alias_name] ||= [])
      i = list.index { |m, _| m == mod }
      return list << [mod, table] unless i

      list[i] = [mod, { values: list[i][1][:values].merge(table[:values]), types: list[i][1][:types].merge(table[:types]) }]
    end

    # What an import's hiding list takes away: "str" and "type:str" keys.
    def hidden_by(imp, table, selection)
      return [] unless imp.hiding

      table[:values].keys.reject { |s| selection[:values].key?(s) } +
        table[:types].keys.reject { |s| selection[:types].key?(s) }.map { |s| "type:#{s}" }
    end

    # The names an import brings in unqualified: {values:, types:}, from a
    # module table; an item the module does not export is an error.
    def import_selection(table, imp, source = '<interactive>')
      wanted = nil
      if imp.items
        wanted = {}
        imp.items.each do |n, subs|
          unless table[:values].key?(n) || table[:types].key?(n)
            raise Error.new(:compile, "Module ‘#{imp.module_name}’ does not export ‘#{n}’", imp.tok.line, imp.tok.col,
                            source)
          end
          wanted[n] = true
          t = table[:types][n]
          if subs == :all && t.is_a?(Name)
            sub_names(t).each { |x| wanted[x] = true }
          elsif subs.is_a?(Array)
            subs.each { |x| wanted[x] = true }
          end
        end
      end
      out = { values: {}, types: {} }
      %i[values types].each do |kind|
        table[kind].each do |str, n|
          out[kind][str] = n if wanted.nil? || (imp.hiding ? !wanted.key?(str) : wanted.key?(str))
        end
      end
      out
    end

    # A type's constructors and fields, or a class's methods (T(..)).
    def sub_names(n)
      if n.kind == :class
        n.klass.methods.map(&:str)
      elsif n.tyinfo
        n.tyinfo.cons.flat_map { |c| [c.str] + (c.fields || []).map(&:str) }
      else
        []
      end
    end

    # `alias.op` fixities for the operators of a module outside the default
    # scope (the default ones are the Prelude's).
    def alias_fixities(alias_name, mod)
      out = {}
      (FixityResolver::MODULE_FIXITIES[mod] || {}).each { |op, f| out["#{alias_name}.#{op}"] = f }
      out
    end

    # `import M`, `import qualified M as N`, `import M (x, T(..))` at the
    # prompt (GHCi: interactive definitions shadow imported names).
    def prompt_import(imp)
      mod = imp.module_name
      table = @names.module_table(mod) || @names.local_module(mod)
      Rhci.module_not_found(mod, imp.tok.line, imp.tok.col, nil, :compile) unless table

      selection = import_selection(table, imp)
      alias_name = imp.as || mod
      under = ((@names.aliases[alias_name] ||= {})[mod] ||= { values: {}, types: {} })
      selection.each { |kind, names| under[kind] = under[kind].merge(names) }
      alias_fixities(alias_name, mod).each { |k, v| @fixities[k] = v }
      @names.default_scope.import(mod, imp.qualified, selection, hidden_by(imp, table, selection)) if DEFAULT_MODULES.include?(mod)
      unless imp.qualified || DEFAULT_MODULES.include?(mod) || @names.local_module(mod)
        selection[:values].each { |str, n| add_prompt_import(@names.imports, str, n) }
        selection[:types].each { |str, n| add_prompt_import(@names.import_types, str, n) }
      end
      Result.new(:ok)
    end

    def add_prompt_import(table, str, n)
      list = (table[str] ||= [])
      list << n unless list.include?(n)
    end

    def add_imports(imported, mod, imp, path)
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
      @names.module_scope = mod[:scope]
      mod[:imported][:values].each do |s, n|
        next if n.is_a?(Array) || n.is_a?(MissingName)

        @names.values[s] = n
        @names.define(s, from_module: true)
      end
      mod[:imported][:types].each do |s, n|
        next if n.is_a?(MissingName)

        @names.types[s] = n
        @names.define(s, type: true, from_module: true)
      end
      mod[:rtop].values.each do |s, n|
        next if s.start_with?('rhci_')

        @names.values[s] = n
        @names.define(s, from_module: true)
      end
      mod[:rtop].types.each do |s, n|
        @names.types[s] = n
        @names.define(s, type: true, from_module: true)
      end
      local = {}
      @modules.each { |name, m| local[name] = m[:exports] }
      @names.local_modules = local
      @fixities = mod[:fixities].dup
      prompt_alias_fixities
    end

    # The build-time snapshot text, if this runtime has one embedded.
    # Lets a host (or a test) supply snapshot text explicitly.
    def self.snapshot_text=(text)
      @embedded_snapshot = text
    end

    # The text, or its parts (see Snapshot::Decoder).
    def self.embedded_snapshot
      return @embedded_snapshot if @embedded_snapshot
      return nil unless Rhci.const_defined?(:PRELUDE_SNAPSHOT_PARTS)

      PRELUDE_SNAPSHOT_PARTS
    end

    # What the snapshot captures after the Prelude has loaded.
    def prelude_state
      [@names, @tenv, @globals, @unfoldings, @full_cores, @specs]
    end

    # Fixities for deriving Show and Read: own (the input's or module's own
    # declarations, which are committed only after it compiles) first, then
    # the prompt's (prompt: false for a module, which has its own scope).
    def fixity_lookup(own = nil, prompt: true)
      table = prompt ? @fixities : {}
      ->(op) { (own && own[op]) || table[op] || FixityResolver::BASE[op] || FixityResolver::DEFAULT }
    end

    # ---- the Prelude -----------------------------------------------------------

    def load_prelude
      return if @prelude_loaded

      @prelude_loaded = true
      snapshot = Session.embedded_snapshot
      if @prelude_mode == :snapshot || (@prelude_mode == :auto && snapshot)
        raise 'no Prelude snapshot is available' unless snapshot

        start = Shim.now
        @decoder = Snapshot.decoder(snapshot)
        @decoder.start_trace if @trace_snapshot
        @names, @tenv, @globals, @unfoldings, @full_cores, @specs = @decoder.root
        capture_baseline
        @preload_time = start && Shim.now - start
        return
      end
      m = Frontend.parse_module(PRELUDE_SOURCE, '<Prelude>', prelude: true)
      rtop = Renamer.new(@names, '<Prelude>', prelude: true).module_decls(m)
      tc = TypeChecker.new(@names, @tenv, '<Prelude>')
      tc.top(rtop)
      defs, = Desugar.new(@names, '<Prelude>').top(rtop)
      commit(rtop, tc, defs, nil, prelude: true)
      LIBRARY_MODULES.each { |mod| compile_library_module(mod) }
      capture_baseline
    rescue StandardError => e
      @prelude_loaded = false
      raise "rhci: the Prelude failed to load: #{e.message}"
    end

    # A library module (prelude/Data/...): compiled like a loaded file, its
    # every top-level name registered for the public modules it implements.
    def compile_library_module(mod)
      label = "<#{mod}>"
      raw = Frontend.parse_module_raw(LIBRARY_SOURCES.fetch(mod), label)
      imported = { values: {}, types: {} }
      scope = DefaultScope.new
      fixities = {}
      qualified = { 'Prelude' => [['Prelude', @names.module_table('Prelude')]] }
      raw.imports.each { |imp| base_import(imp, scope, imported, qualified, fixities, label) }
      m = Frontend.resolve_module(raw, fixities, label)
      layer = FixityResolver.new(fixities, label).group_layer(m.decls)
      renamer = Renamer.new(@names, label, fixity: fixity_lookup(fixities.merge(layer), prompt: false), imported: imported,
                                           module_mode: true,
                                           scope: scope, qualified: qualified, internal: true)
      rtop = renamer.module_decls(m)
      tc = TypeChecker.new(@names, @tenv, label, mode: :file)
      tc.top(rtop)
      defs, = Desugar.new(@names, label).top(rtop)
      install(defs)
      tc.pending.each { |n, sc| @tenv[n] = sc if n.global || n.kind != :var }
      tc.new_instances.each { |(klass, key), inst| add_instance(klass, key, inst) }
      @names.register_library(mod, rtop.values, rtop.types)
    end

    # ---- committing and running --------------------------------------------------

    def commit(rtop, tc, defs, layer, prelude: false)
      install(defs)
      @names.commit(rtop, prelude: prelude)
      tc.pending.each { |n, s| @tenv[n] = s if n.global || n.kind != :var }
      tc.new_instances.each { |(klass, key), inst| add_instance(klass, key, inst) }
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

      @spec_trace << [name, dicts.map { |d| portable_dict(d) }] if @trace_snapshot
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

    # A dictionary expression as global names: "name", or [f, [args...]].
    def portable_dict(d)
      d.is_a?(Core::Var) ? d.name : [portable_dict(d.fn), d.args.map { |a| portable_dict(a) }]
    end

    def self.dict_core(p)
      p.is_a?(String) ? Core::Var.new(p) : Core::App.new(dict_core(p[0]), p[1].map { |a| dict_core(a) })
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

    HELP = <<~TEXT
      Commands (any unambiguous prefix works, :t for :type):
        <expression>          evaluate and print it (IO actions are run); `it` is the result
        <declaration>         define at the prompt (x = 1, f x = ..., data, class, instance)
        :{ ... :}             a multi-line input
        :type <expr>          the expression's type
        :kind <type>          the type's kind
        :info <name>          what a name is: type, class, instances, fixity
        :load <file>...       load modules (prompt definitions are discarded)
        :reload               load the same files again
        :quit                 leave (or Ctrl-D)
        :?, :help             this text
      Ctrl-C interrupts an evaluation. History is kept in ~/.rhci_history.
    TEXT

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
      when 'info' then info(arg)
      when 'kind' then kind_of(arg)
      when 'load' then load(Rhci::Text.strip(arg).split(' '))
      when 'reload' then reload
      when '?', 'help'
        write_text(HELP)
        Result.new(:ok)
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
