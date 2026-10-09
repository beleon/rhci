# frozen_string_literal: true

# Flags Ruby constructs that are missing from our lean mruby build (see
# CLAUDE.md "mruby facts") in every file that runs on mruby. Crude by design:
# a false positive is silenced with a trailing `# lint:ok` and a reason.
ROOT = File.expand_path('..', __dir__)

RULES = [
  [/\bStruct\b/, 'Struct is not in the mruby build'],
  [/\bSet\b/, 'Set is not in the mruby build'],
  [/\b(catch|throw)\b/, 'catch/throw are not in the mruby build'],
  [/\bFiber\b/, 'Fiber is not in the mruby build'],
  [/\b(format|sprintf|printf)\b/, 'no sprintf/format in the mruby build'],
  [/['"]\s*%\s/, 'String#% is not in the mruby build'],
  [/\.(un)?pack1?\b/, 'pack/unpack are not in the mruby build'],
  [/instance_variable_(get|set)/, 'not in the mruby build'],
  [/\bObjectSpace\b/, 'ObjectSpace is not in the mruby build'],
  [/\bTime\b/, 'Time is not in the mruby build'],
  [/\b(StringIO|Comparable#clamp)\b|\.clamp\b|\.curry\b/, 'not in the mruby build'],
  [/\brequire(_relative)?\b/, 'mruby has no require; add the file to lib/rhci/manifest.txt'],
  [/\.(each_char|each_byte|each_line|chars_each|each_with_index|each_slice|each_cons)(?!\s*(\{|do\b|\())/,
   'blockless enumerators need Fiber on mruby'],
  [/round\(\s*half:/, 'round(half:) fails on mruby'],
  [/=~|\.match\(|\bRegexp\b|\.(sub|gsub|scan)\(\s*\//, 'no Regexp in the mruby build'],
  [/^\s*in\s/, 'case/in pattern matching is not used'],
  [/\.to_s\b.*Float|Float.*\.to_s\b/, 'never print Floats with Ruby (mruby uses %.15g)'],
  [/\$!/, 'mruby leaves $! nil inside a rescue modifier; use begin/rescue => e'],
  [/^\s*class (Range|Array|Hash|String|Integer|Float|Proc|Method|Module|Class|Struct|Symbol|Comparable|Kernel|Data|Set|Time|IO|File) /,
   'mruby resolves this to the core class inside includers; pick another name']
].freeze

files = File.read(File.join(ROOT, 'lib', 'rhci', 'manifest.txt')).split("\n").map do |n|
  File.join(ROOT, 'lib', 'rhci', "#{n}.rb")
end
files += [File.join(ROOT, 'test', 'harness.rb'), File.join(ROOT, 'test', 'oracle.rb')] +
         Dir[File.join(ROOT, 'test', 'unit', '*_test.rb')]
exempt = [File.join(ROOT, 'lib', 'rhci', 'shim.rb')]

problems = []
(files - exempt).sort.each do |path|
  File.readlines(path).each_with_index do |line, i|
    code = line.sub(/#.*\z/m, '') # crude: drops comments (and anything after a # in strings)
    next if line.include?('# lint:ok')

    RULES.each do |re, why|
      problems << "#{path.sub("#{ROOT}/", '')}:#{i + 1}: #{why}\n    #{line.strip}" if code =~ re
    end
  end
end
puts problems
puts "lint: #{files.length} files, #{problems.length} problems"
exit(problems.empty? ? 0 : 1)
