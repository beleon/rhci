# Runtime capability probe: run on both runtimes and diff.
#   ruby tools/runtime_probe.rb; build/mruby/bin/mruby tools/runtime_probe.rb
def t(label)
  r = begin; yield.inspect; rescue Exception => e; "RAISE #{e.class}: #{e.message[0,60]}"; end
  puts "#{label.ljust(28)} #{r}"
end
t("0.1+0.2")        { (0.1+0.2).to_s }
t("12345678.9")     { 12345678.9.to_s }
t("0.05")           { 0.05.to_s }
t("1e22")           { 1e22.to_s }
t("1e16")           { 1e16.to_s }
t("5e-324")         { 5.0e-324.to_s }
t("-0.0")           { (-0.0).to_s }
t("1/0.0")          { (1/0.0).to_s }
t("0/0.0")          { (0/0.0).to_s }
t("2**64")          { 2**64 }
t("max+1")          { 9223372036854775807 + 1 }
t("min-1")          { -9223372036854775808 - 1 }
t("big*big")        { (2**64) * (2**64) }
t("25!")            { (1..25).inject(:*) }
t("big.class")      { (2**64).class }
t("-7/2 (div)")     { -7 / 2 }
t("-7%2 (mod)")     { -7 % 2 }
t("-7.remainder 2") { -7.remainder(2) }
t("(2**70)%7")      { (2**70) % 7 }
t("-(2**70)/3")     { -(2**70) / 3 }
t("2.5.round")      { 2.5.round }
t("2.5.round even") { 2.5.round(half: :even) }
t("1e20.to_i")      { 1e20.to_i }
t("(2**70).to_f")   { (2**70).to_f }
t("utf8 length")    { "café".length }
t("utf8 [3]")       { "café"[3] }
t("ord λ")          { "λ".ord }
t("chr 955")        { 955.chr(Encoding::UTF_8) rescue 955.chr }
t("[955].pack")     { [955].pack("U") }
t("Math.sqrt 2")    { Math.sqrt(2) }
t("Float#nan?")     { (0/0.0).nan? }
t("Integer#pow mod"){ 3.pow(4, 5) }
t("Integer.sqrt")   { Integer.sqrt(17) }
t("frozen literal") { "a" << "b" }
t("Struct")         { Struct.new(:a).new(1).a }
t("Set")            { Set.new([1]).size }
t("Comparable")     { 1.clamp(2, 3) }
t("Proc curry")     { ->(a,b){a+b}.curry[1][2] }
t("Hash#compare_by_identity") { h = {}.compare_by_identity; h.size }
t("ObjectSpace")    { ObjectSpace.respond_to?(:each_object) }
t("object_id")      { Object.new.object_id.is_a?(Integer) }
t("catch/throw")    { catch(:x) { throw :x, 1 } }
t("Fiber")          { Fiber.new { 1 }.resume }
t("method_missing ok") { 1.respond_to?(:+) }
def deep(n); n == 0 ? 0 : 1 + deep(n - 1); end
[1000, 10_000, 100_000, 1_000_000].each { |n| t("recursion #{n}") { deep(n) } }
t("frexp 0.1")        { Math.frexp(0.1) }
t("ldexp")            { Math.ldexp(0.5, 3) }
t("frexp 5e-324")     { Math.frexp(5.0e-324) }
t("0.1+0.2 == 0.30000000000000004") { 0.1 + 0.2 == 0.30000000000000004 }
t("to_f parse exact") { "0.30000000000000004".to_f == 0.1 + 0.2 }
t("to_f 5e-324")      { "5.0e-324".to_f > 0 }
t("Float#inspect")    { (0.1+0.2).inspect }
t("Float#to_i 1e18")  { 1e18.to_i }
t("Float#floor big")  { 1e20.floor }
t("Integer#chr")      { 97.chr }
t("UTF8 via [].pack?"){ [955].respond_to?(:pack) }
t("String#<< int")    { s = ""; s << 955; s }
t("String#codepoints"){ "aλ".codepoints rescue "aλ".each_char.map(&:ord) }
t("each_char")        { "aλ".each_char.to_a }
t("bytes")            { "λ".bytes }
t("bytes→str")        { [206, 187].map(&:chr).join }
t("force_encoding?")  { "".respond_to?(:force_encoding) }
t("int64 wrap via &") { ((9223372036854775807 + 1 + 2**63) % 2**64) - 2**63 }
t("Float == Integer") { 3 == 3.0 }
t("Hash with array key") { {[1,2] => 3}[[1,2]] }
t("Comparable on Array") { [1,2] <=> [1,3] }
t("respond_to? __method__") { __method__ }
t("instance_variable_get") { Object.new.instance_variable_get(:@x) }
t("String#%")         { "%d" % 1 }
t("Kernel#format")    { format("%d", 1) }
t("Integer#digits")   { 123.digits }
t("Integer#bit_length") { (2**70).bit_length }
t("big >> 3")         { (2**70) >> 3 }
t("Float::MAX")       { Float::MAX }
t("Float::EPSILON")   { Float::EPSILON }
t("Float::DIG")       { Float::DIG rescue nil }
