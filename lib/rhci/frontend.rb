# frozen_string_literal: true

module Rhci
  # Source text to fixity-resolved syntax: lexer, layout, parser, fixity.
  module Frontend
    # A GHCi input. Returns [node, fixity_layer]; see FixityResolver#repl.
    def self.parse_repl(src, fixities = nil, source = '<interactive>')
      node = Parser.new(src, source).parse_repl
      FixityResolver.new(fixities, source).repl(node)
    end

    # A bare expression (the argument of :type, `rhci -c` pieces).
    def self.parse_expression(src, fixities = nil, source = '<interactive>')
      e = Parser.new(src, source).parse_expression
      FixityResolver.new(fixities, source).expr(e)
    end

    # A module, parsed but with operators unresolved: imported fixities are
    # only known once its imports are loaded (see resolve_module).
    def self.parse_module_raw(src, source)
      Parser.new(src, source).parse_module
    end

    def self.resolve_module(m, fixities, source)
      FixityResolver.new(fixities, source).module_decl(m)
    end

    def self.parse_module(src, source, prelude: false)
      m = Parser.new(src, source, prelude: prelude).parse_module
      FixityResolver.new(nil, source).module_decl(m)
    end
  end
end
