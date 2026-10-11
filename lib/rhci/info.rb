# frozen_string_literal: true

module Rhci
  # :info and :kind. The content is GHCi's (a name's type and fixity; a
  # type's or class's declaration and instances; a type's kind); the layout
  # is similar but GHCi's `-- Defined in` notes are left out.
  class Session
    # :info NAME... (several names, each reported in turn).
    def info(arg)
      names = Rhci::Text.strip(arg).split(' ')
      return Result.new(:command_error, 'syntax: :info <name>') if names.empty?

      load_prelude

      renamer = Renamer.new(@names, fixity: fixity_lookup)
      names.each do |raw|
        str = raw.start_with?('(') && raw.end_with?(')') && raw.length > 2 ? raw[1..-2] : raw
        lines = info_lines(renamer, str)
        return Result.new(:scope_error, "Not in scope: ‘#{str}’") if lines.empty?

        write_text(lines.join("\n") + "\n")
      end
      Result.new(:ok)
    end

    # :kind TYPE
    def kind_of(arg)
      src = Rhci::Text.strip(arg)
      return Result.new(:command_error, 'syntax: :kind <type>') if src.empty?

      load_prelude

      ty = Parser.new(src).parse_type_expression
      Renamer.new(@names, fixity: fixity_lookup).rename_type(ty)
      write_text("#{src} :: #{Kinds.show(Kinds.new.kind_of(ty))}\n")
      Result.new(:ok)
    end

    private

    def info_lines(renamer, str)
      out = []
      v = renamer.lookup_entity(:values, str)
      t = AST.ident_start?(str[-1]) || str.include?('.') ? renamer.lookup_entity(:types, str) : nil
      if v
        if v.method_of
          out.concat(class_lines(v.method_of))
        elsif v.kind == :con && v.tyinfo
          out.concat(type_lines(v.tyinfo.name))
        else
          out << "#{op_name(v.str)} :: #{scheme_text(v)}"
        end
        f = fixity_lookup.call(v.str)
        out << "#{fixity_word(f[0])} #{f[1]} #{op_or_backtick(v.str)}" if f != FixityResolver::DEFAULT
      end
      out.concat(type_lines(t)) if t && !(v && v.kind == :con && v.tyinfo && v.tyinfo.name.equal?(t))
      out
    end

    def fixity_word(assoc)
      { left: 'infixl', right: 'infixr', none: 'infix' }[assoc]
    end

    def op_name(str)
      AST.ident_start?(str[0]) ? str : "(#{str})"
    end

    def op_or_backtick(str)
      AST.ident_start?(str[0]) ? "`#{str}`" : str
    end

    def scheme_text(n)
      s = @tenv[n]
      s ? Types::Printer.new.scheme(s) : '?'
    end

    # A type constructor's or class's declaration, then its instances.
    def type_lines(n)
      return class_lines(n.klass) if n.kind == :class

      ti = n.tyinfo
      return [] unless ti

      out = []
      if ti.synonym
        out << "type #{([n.str] + ti.params).join(' ')} = #{type_ast_text(ti.synonym[1])}"
        return out
      end
      cons = ti.cons.map { |c| con_text(ti, c) }
      head = ([n.str] + ti.params).join(' ')
      if ti.cons.empty? && ti.tcon && BUILTIN_DATA[n.str]
        out << BUILTIN_DATA[n.str]
      else
        out << "#{ti.newtype ? 'newtype' : 'data'} #{head}#{cons.empty? ? '' : " = #{cons.join(' | ')}"}"
      end
      out.concat(instance_lines { |inst| inst.head.equal?(ti.tcon) })
      out
    end

    BUILTIN_DATA = {
      'Int' => 'data Int = I# Int#', 'Integer' => 'data Integer = IS Int# | IP BigNat# | IN BigNat#',
      'Char' => 'data Char = C# Char#', 'Double' => 'data Double = D# Double#'
    }.freeze

    def type_ast_text(t)
      case t
      when AST::TCon, AST::TVar then t.name
      when AST::TList then "[#{type_ast_text(t.elem)}]"
      when AST::TTuple then "(#{t.elems.map { |e| type_ast_text(e) }.join(', ')})"
      when AST::TFun then "#{type_ast_text(t.from)} -> #{type_ast_text(t.to)}"
      when AST::TApp then ([type_ast_text(t.fn)] + t.args.map { |a| "(#{type_ast_text(a)})" }).join(' ')
      else '?'
      end
    end

    # A constructor as the data declaration writes it.
    def con_text(ti, c)
      s = @tenv[c]
      return c.str unless s

      printer = Types::Printer.new
      args = []
      t = s.type
      while (sp = Types.spine(t)) && sp[0].equal?(Types::ARROW) && sp[1].length == 2
        args << sp[1][0]
        t = sp[1][1]
      end
      _, res_args = Types.spine(t)
      res_args.each_with_index { |a, i| printer.name_gen(a.index, ti.params[i]) if a.is_a?(Types::TGen) }
      strict = c.strict || []
      fields = []
      args.each_with_index { |a, i| fields << "#{strict[i] ? '!' : ''}#{printer.type(a, 2)}" }
      if c.fields && !c.fields.empty?
        parts = []
        c.fields.each_with_index { |f, i| parts << "#{op_name(f.str)} :: #{strict[i] ? '!' : ''}#{printer.type(args[i], strict[i] ? 2 : 0)}" }
        "#{op_name(c.str)} {#{parts.join(', ')}}"
      elsif !AST.ident_start?(c.str[0]) && fields.length == 2
        "#{fields[0]} #{c.str} #{fields[1]}"
      else
        ([op_name(c.str)] + fields).join(' ')
      end
    end

    def class_lines(ci)
      supers = (ci.supers || []).map { |sc| "#{sc.name.str} #{ci.tyvar}" }
      ctx = if supers.empty? then ''
            elsif supers.length == 1 then "#{supers[0]} => "
            else "(#{supers.join(', ')}) => "
            end
      out = ["class #{ctx}#{ci.name.str} #{ci.tyvar} where"]
      ci.methods.each { |m| out << "  #{op_name(m.str)} :: #{method_text(ci, m)}" }
      out.concat(instance_lines { |inst| inst.klass.equal?(ci) })
      out
    end

    # A method's type inside its class: the class's own constraint left out
    # and its variable named as the class declaration names it.
    def method_text(ci, m)
      s = @tenv[m]
      return '?' unless s

      own = s.preds.find { |c, ty| (c.equal?(ci) || (c.respond_to?(:name) && c.name.equal?(ci.name))) && ty.is_a?(Types::TGen) }
      printer = Types::Printer.new
      printer.name_gen(own[1].index, ci.tyvar) if own
      rest = s.preds.reject { |p| p.equal?(own) }
      body = printer.type(s.type)
      return body if rest.empty?

      ctx = rest.map { |c, ty| "#{c.respond_to?(:name) ? c.name.str : c} #{printer.type(ty, 2)}" }
      "#{ctx.length == 1 ? ctx[0] : "(#{ctx.join(', ')})"} => #{body}"
    end

    # `instance` lines for the instances selected by the block, in scope.
    # Instances for rhci's own helper types (which no module exports) are
    # left out.
    def instance_lines
      out = []
      seen = {}
      renamer = Renamer.new(@names, fixity: fixity_lookup)
      @names.types.each_value do |n|
        next unless n.kind == :class && n.klass && !seen.key?(n.klass)

        seen[n.klass] = true
        (n.klass.instances || {}).each_value do |inst|
          next unless yield(inst)
          next unless nameable_type?(inst.head, renamer)

          out << instance_text(inst)
        end
      end
      out.sort
    end

    def nameable_type?(tcon, renamer)
      return true unless tcon && AST.ident_start?(tcon.name[0])
      return true if renamer.lookup_entity(:types, tcon.name)

      unless @exported_types
        @exported_types = {}
        MODULE_EXPORTS.each_value { |_, types| types.each { |t| @exported_types[t] = true } }
      end
      @exported_types.key?(tcon.name)
    end

    def instance_text(inst)
      vars = inst.tyvars || []
      ctx = (inst.context || []).map do |klass, i|
        name = klass.respond_to?(:name) ? klass.name.str : klass.to_s
        "#{name} #{vars[i]}"
      end
      (inst.equalities || {}).each { |i, t| ctx << "#{vars[i]} ~ #{Types::Printer.new.type(t)}" }
      ctx_s = if ctx.empty? then ''
              elsif ctx.length == 1 then "#{ctx[0]} => "
              else "(#{ctx.join(', ')}) => "
              end
      "instance #{ctx_s}#{inst.klass.name.str} #{instance_head_text(inst.head, vars)}"
    end

    def instance_head_text(head, vars)
      name = head.name
      if name == '[]' then vars.empty? ? '[]' : "[#{vars[0]}]"
      elsif name == '->' then vars.length == 2 ? "(#{vars[0]} -> #{vars[1]})" : (vars.empty? ? '(->)' : "((->) #{vars[0]})")
      elsif name.start_with?('(,') then vars.length == head.arity ? "(#{vars.join(', ')})" : "(#{([name] + vars).join(' ')})"
      elsif vars.empty? then name
      else "(#{([name] + vars).join(' ')})"
      end
    end
  end
end
