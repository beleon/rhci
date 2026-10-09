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
    def initialize(stdout: nil, stdin: nil, limits: nil, prelude: :auto)
      @prelude_mode = prelude
      @stdout = stdout
      @stdin = stdin
      @limits = limits
      @names = NameEnv.new
      @tenv = {}
      @globals = {}
      @fixities = {}
      @machine = VM::Machine.new(stdout, limits)
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
    def eval_expression(expr, layer, raw_strings: false, arity_args: nil, want: nil)
      # `let it = e` is not recursive: `it` inside e is the previous one. So
      # the binding gets an internal name and becomes `it` once committed.
      @it_count = (@it_count || 0) + 1
      internal = "rhci_it#{@it_count}"
      it_decl = AST::FunEq.new(expr.tok, internal, [], AST::Rhs.new(expr.tok, expr, nil, nil))
      rtop = Renamer.new(@names, fixity: fixity_lookup).repl(AST::ReplDecls.new(expr.tok, [it_decl]))
      tc = TypeChecker.new(@names, @tenv)
      tc.top(rtop)
      it_name = rtop.values[internal]
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
      raise UnsupportedError, '-i is not implemented yet' if interact

      e = command_expression(expr, args)
      load_prelude
      eval_expression(e, nil, raw_strings: true, arity_args: args.length, want: :pure)
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
      raise UnsupportedError, '-i is not implemented yet' if interact
      raise UnsupportedError, 'getArgs is not implemented yet' unless args.empty?

      e = Frontend.parse_expression(expr, @fixities)
      load_prelude
      eval_expression(e, nil, raw_strings: true, want: :io)
    rescue Error => e
      failure(e)
    rescue VM::HsException => e
      @machine.flush_output
      Result.new(:exception, @machine.exception_message(e))
    rescue VM::LimitExceeded => e
      @machine.flush_output
      Result.new(:limit, e.message)
    end

    def command_expression(expr, args)
      e = Frontend.parse_expression(expr, @fixities)
      return e if args.empty?

      arg_nodes = args.map { |a| AST::Paren.new(nil, Frontend.parse_expression(a, @fixities)) }
      AST::App.new(e.tok, AST::Paren.new(e.tok, e), arg_nodes)
    end

    # `:load PATH...` / `rhci PATH...`: replace the loaded modules.
    def load(paths)
      Result.new(:unsupported, ':load is not implemented yet')
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
      [@names, @tenv, @globals]
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

        @names, @tenv, @globals = Snapshot.decode(snapshot)
        return
      end
      m = Frontend.parse_module(PRELUDE_SOURCE, '<Prelude>', prelude: true)
      rtop = Renamer.new(@names, '<Prelude>', prelude: true).module_decls(m)
      tc = TypeChecker.new(@names, @tenv, '<Prelude>')
      tc.top(rtop)
      defs, = Desugar.new(@names, '<Prelude>').top(rtop)
      commit(rtop, tc, defs, nil, prelude: true)
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
      table = @globals.dup
      cells.each { |c| table[c.name] = c }
      lower = Lower.new(table)
      values = defs.map { |name, core| lower.global_value(name, core) }
      cells.each_with_index { |c, i| c.value = values[i] }
      @globals = table
    end

    def eval_core(core)
      code = Lower.new(@globals).expression(core)
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
