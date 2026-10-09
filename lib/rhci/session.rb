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

    def initialize(stdout: nil, stdin: nil, limits: nil)
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
      rtop = Renamer.new(@names).repl(node)
      return Result.new(:ok) if rtop.import

      tc = TypeChecker.new(@names, @tenv)
      t = tc.top(rtop)
      if node.is_a?(AST::ReplExpr)
        check_printable(t, node)
        defs, core = Desugar.new(@names).top(rtop)
        commit(rtop, tc, defs, layer)
        run_expression(core, t)
      elsif node.is_a?(AST::ReplBind)
        result_ok = io_result_type(t)
        raise UnsupportedError, 'binding the result of an IO action needs type classes' unless result_ok

        defs, core = Desugar.new(@names).top(rtop)
        commit(rtop, tc, defs, layer)
        bind_io_result(core, node, rtop)
      else
        defs, = Desugar.new(@names).top(rtop)
        commit(rtop, tc, defs, layer)
        Result.new(:ok)
      end
    end

    # `rhci -c EXPR ARG...`: apply a pure EXPR to ARGs, each a Haskell
    # expression.
    def run_pure(expr, args, interact: false)
      raise UnsupportedError, '-i is not implemented yet' if interact

      e = Frontend.parse_expression(expr, @fixities)
      arg_nodes = args.map { |a| Frontend.parse_expression(a, @fixities) }
      e = AST::App.new(e.tok, AST::Paren.new(e.tok, e), arg_nodes.map { |a| AST::Paren.new(a.tok, a) }) unless args.empty?
      load_prelude
      Renamer.new(@names).expression(e)
      tc = TypeChecker.new(@names, @tenv)
      s = tc.expression_scheme(e)
      t = s.type
      if Types.split_fn(t)
        raise Error.new(:compile, "#{expr} expects more arguments than the #{args.length} given")
      end
      if io_type?(t)
        raise Error.new(:compile, "#{expr} is an IO action; use rhci -x to run it")
      end
      unless string_type?(t)
        raise UnsupportedError, 'printing values other than Strings needs type classes, which are not implemented yet'
      end

      core = Desugar.new(@names).expression(e)
      write_string(eval_core(core))
      Result.new(:ok)
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
      Renamer.new(@names).expression(e)
      t = TypeChecker.new(@names, @tenv).expression_scheme(e).type
      raise Error.new(:compile, "#{expr} is not an IO action; use rhci -c to evaluate it") unless io_type?(t)
      raise UnsupportedError, 'printing the result of an IO action needs type classes' unless io_result_type(t)

      run_io_value(eval_core(Desugar.new(@names).expression(e)))
      Result.new(:ok)
    rescue Error => e
      failure(e)
    rescue VM::HsException => e
      @machine.flush_output
      Result.new(:exception, @machine.exception_message(e))
    rescue VM::LimitExceeded => e
      @machine.flush_output
      Result.new(:limit, e.message)
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

    # ---- the Prelude -----------------------------------------------------------

    def load_prelude
      return if @prelude_loaded

      @prelude_loaded = true
      m = Frontend.parse_module(PRELUDE_SOURCE, '<Prelude>', prelude: true)
      rtop = Renamer.new(@names, '<Prelude>', prelude: true).module_decls(m)
      tc = TypeChecker.new(@names, @tenv, '<Prelude>')
      tc.top(rtop)
      defs, = Desugar.new(@names, '<Prelude>').top(rtop)
      commit(rtop, tc, defs, nil)
    rescue StandardError => e
      @prelude_loaded = false
      raise "rhci: the Prelude failed to load: #{e.message}"
    end

    # ---- committing and running --------------------------------------------------

    def commit(rtop, tc, defs, layer)
      cells = defs.map { |name, _| VM::Cell.new(name) }
      table = @globals.dup
      cells.each { |c| table[c.name] = c }
      lower = Lower.new(table)
      values = defs.map { |name, core| lower.global_value(name, core) }
      cells.each_with_index { |c, i| c.value = values[i] }
      @globals = table
      @names.commit(rtop)
      tc.pending.each { |n, s| @tenv[n] = s if n.global || n.kind != :var }
      layer&.each { |k, v| @fixities[k] = v }
    end

    def eval_core(core)
      code = Lower.new(@globals).expression(core)
      @machine.eval_code(code)
    end

    def run_expression(core, _type)
      run_io_value(eval_core(core))
      Result.new(:ok)
    end

    # A String result is written raw (no quotes), as it is produced.
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

    def bind_io_result(core, node, rtop)
      value = run_io_value(eval_core(core))
      cell = VM::Cell.new('it%result', value)
      @globals = @globals.merge(cell.name => cell)
      ds = Desugar.new(@names)
      defs = rtop.values.values.map do |n|
        sel = ds.match_value(cell.name, node.pat, Core::Var.new(n.core),
                             Core::Prim.new(:raise, [Core::Var.new('it%msg')]))
        [n.core, sel]
      end
      msg = VM::Cell.new('it%msg', @machine.send(:str_value, 'Irrefutable pattern failed'))
      @globals = @globals.merge(msg.name => msg)
      cells = defs.map { |name, _| VM::Cell.new(name) }
      table = @globals.dup
      cells.each { |c| table[c.name] = c }
      lower = Lower.new(table)
      cells.each_with_index { |c, i| c.value = lower.global_value(c.name, defs[i][1]) }
      @globals = table
      Result.new(:ok)
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

    # ---- types ---------------------------------------------------------------------

    # At the prompt only IO () runs for now: printing any value (even a
    # String, which GHCi shows quoted) needs Show.
    def check_printable(t, _node)
      return if io_type?(t) && io_result_type(t)

      raise UnsupportedError, 'printing values needs type classes, which are not implemented yet'
    end

    def io_type?(t)
      h, args = Types.spine(t)
      io = @names.types['IO']
      h.is_a?(Types::TCon) && io && h.key == io.tyinfo.tcon.key && args.length == 1
    end

    # True if an IO action's result needs no printing (it is ()).
    def io_result_type(t)
      _, args = Types.spine(t)
      r = Types.prune(args[0])
      r.is_a?(Types::TCon) && r.equal?(Types::UNIT)
    end

    def string_type?(t)
      h, args = Types.spine(t)
      h.equal?(Types::LIST) && Types.prune(args[0]).equal?(Types::CHAR)
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
