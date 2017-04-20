$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'logglier'

log = Logglier.new('http://requestb.in/x4ue08x4', threaded: true, bulk: true, format: :json, bulk_max_size: 3)

10.times do |i|
  log.info({ hello: "world", i: i })
end

