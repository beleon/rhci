# frozen_string_literal: true

# Runs the exercism Haskell track's test suites (reference solutions) on
# rhci and on real GHC, and compares them. See test/exercism/README.md.
#
#   ruby test/exercism/run.rb [--ghc] [--mruby] [exercise...]
#
# --ghc reruns GHC (its results are cached in build/exercism); --mruby runs
# the mruby binary instead of an in-process CRuby session.
require 'fileutils'

# A runaway evaluation must fail here (NoMemoryError), not take the machine
# down: 4 ^ (2 ^ 127) once grew a run to 85 GB. Subprocesses (the mruby
# runner, the binary) inherit the limit.
Process.setrlimit(:AS, 8 * 2**30)
require 'open3'
require_relative '../../lib/rhci'

module Exercism
  ROOT = File.expand_path('../..', __dir__)
  TRACK = File.join(ROOT, 'vendor', 'exercism-haskell', 'exercises', 'practice')
  WORK = File.join(ROOT, 'build', 'exercism')
  SHIM = File.join(__dir__, 'shim')
  IMAGE = 'docker.io/library/haskell:9.6'

  module_function

  def ensure_track
    return if Dir.exist?(TRACK)

    system('git', 'clone', '--depth', '1', 'https://github.com/exercism/haskell.git',
           File.join(ROOT, 'vendor', 'exercism-haskell'), exception: true)
  end

  # ---- preparing an exercise ----------------------------------------------------

  def prepare(name)
    dir = File.join(WORK, name)
    FileUtils.rm_rf(dir)
    FileUtils.mkdir_p(dir)
    FileUtils.cp_r(File.join(SHIM, '.'), dir)
    src = File.join(example_dir(name), 'src')
    sources = Dir[File.join(src, '**', '*.hs')]
    sources.each do |f|
      dest = File.join(dir, f.sub("#{src}/", ''))
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(f, dest)
    end
    texts = sources.map { |f| File.read(f) }
    tests = File.read(File.join(TRACK, name, 'test', 'Tests.hs'))
    File.write(File.join(dir, 'Tests.hs'), expand_wildcards(tests, texts + [tests]))
    dir
  end

  # The reference solution: success-standard, or the variant that needs
  # the fewest extensions (lists rather than Text).
  PREFERRED = %w[success-standard success-liststring success-simple success-double].freeze

  def example_dir(name)
    base = File.join(TRACK, name, '.meta', 'examples')
    found = PREFERRED.find { |d| Dir.exist?(File.join(base, d)) }
    found ||= Dir.children(base).sort.find { |d| d.start_with?('success') }
    File.join(base, found)
  end

  # RecordWildCards appears only in the tests' scaffolding (`test Case{..}
  # = ...`): C{..} becomes C{f = f, ...}, which is Haskell 98, and the
  # extension is dropped from the pragma. rhci's language is unchanged.
  def expand_wildcards(text, all_texts)
    return text unless text.include?('{..}')

    fields = record_fields(all_texts.join("\n"))
    out = text.gsub(/\b([A-Z][\w']*)\s*\{\.\.\}/) do
      con = Regexp.last_match(1)
      fs = fields[con] or raise "#{con}{..}: fields unknown"
      "#{con} {#{fs.map { |f| "#{f} = #{f}" }.join(', ')}}"
    end
    out.gsub(/\{-#\s*LANGUAGE([^#]*)#-\}/) do
      exts = Regexp.last_match(1).split(',').map(&:strip).reject { |e| e.empty? || e == 'RecordWildCards' }
      exts.empty? ? '' : "{-# LANGUAGE #{exts.join(', ')} #-}"
    end
  end

  # Constructor => field names, from record declarations.
  def record_fields(text)
    fields = {}
    text.scan(/\b([A-Z][\w']*)\s*\{([^{}]*::[^{}]*)\}/m) do |con, body|
      # "a, b :: T, c :: (U, V)": split at top-level commas; a segment is
      # "name :: type", or a bare name grouped with the next.
      names = top_level_split(body).map { |seg| seg.split('::')[0].strip }
      fields[con] ||= names if names.all? { |n| n.match?(/\A[a-z_][\w']*\z/) }
    end
    fields
  end

  def top_level_split(text)
    parts = ['']
    depth = 0
    text.each_char do |c|
      depth += 1 if '([{'.include?(c)
      depth -= 1 if ')]}'.include?(c)
      if c == ',' && depth.zero?
        parts << ''
      else
        parts[-1] += c
      end
    end
    parts
  end

  # ---- GHC (cached) -------------------------------------------------------------------

  def run_ghc(names)
    script = names.map do |n|
      "cd /w/#{n} && (timeout 300 runghc -i. Tests.hs > ghc.out 2> ghc.err; echo $? > ghc.status); cd /w"
    end.join("\n")
    Open3.capture3('podman', 'run', '--rm', '-i', '--memory', '8g', '-v', "#{WORK}:/w:Z", '-w', '/w', IMAGE, 'sh', '-c', script)
  end

  def ghc_result(dir)
    status = File.join(dir, 'ghc.status')
    return nil unless File.exist?(status)

    [File.read(status).to_i, File.read(File.join(dir, 'ghc.out'))]
  end

  # ---- rhci ---------------------------------------------------------------------------

  class Sink
    attr_reader :text

    def initialize
      @text = +''
    end

    def write(s)
      @text << s
      s.length
    end

    def flush; end
  end

  # [status, stdout, message]: status :ok, :load (with the load result's
  # status), :exception, :limit or :unsupported.
  def run_rhci(dir, mruby: false)
    return run_binary(dir) if mruby

    out = Sink.new
    err = Sink.new
    deadline = Rhci::Shim.now + 120
    s = Rhci::Session.new(stdout: out, stderr: err, cwd: dir, limits: { deadline: deadline })
    r = s.eval(':load Tests')
    return [r.status == :unsupported ? :unsupported : :load, out.text, "#{r.status}: #{r.message}"] unless r.ok?

    before = out.text.length
    r = s.eval('main')
    [r.ok? ? :ok : r.status, out.text[before..-1], r.message.to_s]
  rescue StandardError => e
    [:crash, '', "#{e.class}: #{e.message.lines.first.to_s.strip}"]
  end

  def run_binary(dir)
    exe = File.join(ROOT, 'build', 'rhci', 'bin', 'rhci')
    out, err, st = Open3.capture3('timeout', '120', exe, stdin_data: ":load Tests\nmain\n", chdir: dir)
    return [:limit, '', 'time limit exceeded'] if st.exitstatus == 124
    prompt = Rhci::CLI::PROMPT
    out = out.gsub(prompt, '').sub(/\n\z/, '').sub(/\AOk, .*loaded\.\n/, '')
    status = if err.include?('unsupported') then :unsupported
             elsif err.include?('*** Exception') then :exception
             elsif !err.empty? then :load
             else :ok
             end
    [status, out, err.lines.first.to_s.strip]
  end

  # ---- comparing ----------------------------------------------------------------------

  def classify(ghc, rhci)
    if ghc[0] != 0
      return [:ghc_failed, "GHC: #{ghc[2].to_s[/Could not find module ‘[^’]*’|error:.*/] || "exit #{ghc[0]}"}"]
    end

    status, out, msg = rhci
    case status
    when :unsupported then [:unsupported, msg]
    when :load then [:BUG, "rejected: #{msg}"]
    when :crash then [:BUG, "internal error: #{msg}"]
    when :limit then [:slow, msg]
    when :ok
      out == ghc[1] ? [:pass, ''] : [:BUG, "output differs: #{first_difference(ghc[1], out)}"]
    else [:BUG, "#{status}: #{msg}"]
    end
  end

  def first_difference(want, got)
    w = want.lines
    g = got.lines
    i = 0
    i += 1 while i < w.length && w[i] == g[i]
    "line #{i + 1}: GHC #{w[i].inspect}, rhci #{g[i].inspect}"
  end

  def main(argv)
    ensure_track
    ghc = argv.delete('--ghc')
    mruby = argv.delete('--mruby')
    names = argv.empty? ? Dir.children(TRACK).sort : argv
    dirs = names.to_h { |n| [n, prepare(n)] }
    missing = names.select { |n| ghc || ghc_result_cache(n).nil? }
    unless missing.empty?
      run_ghc(missing)
      FileUtils.mkdir_p(File.join(WORK, '.ghc'))
      missing.each do |n|
        r = ghc_result(dirs[n]) or next
        File.write(File.join(WORK, '.ghc', "#{n}.status"), r[0].to_s)
        File.write(File.join(WORK, '.ghc', "#{n}.out"), r[1])
        File.write(File.join(WORK, '.ghc', "#{n}.err"), File.read(File.join(dirs[n], 'ghc.err')))
      end
    end
    counts = Hash.new(0)
    names.each do |n|
      g = ghc_result_cache(n) || [-1, '']
      kind, detail = classify(g, run_rhci(dirs[n], mruby: mruby))
      counts[kind] += 1
      puts format('%-12s %-24s %s', kind, n, detail[0, 160])
    end
    puts counts.map { |k, v| "#{k} #{v}" }.join(', ')
  end

  # GHC's results survive re-preparing a directory.
  def ghc_result_cache(name)
    path = File.join(WORK, '.ghc', name)
    return nil unless File.exist?("#{path}.status")

    err = File.exist?("#{path}.err") ? File.read("#{path}.err") : ''
    [File.read("#{path}.status").to_i, File.read("#{path}.out"), err]
  end
end

Exercism.main(ARGV) if __FILE__ == $PROGRAM_NAME
