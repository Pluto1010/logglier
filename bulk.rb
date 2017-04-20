$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'logglier'

#url = "http://logs-01.loggly.com/bulk/TOKEN/tag/bulk/"
url = "http://requestb.in/x4ue08x4"

log = Logglier.new(, threaded: true, bulk: true, format: :json, bulk_max_size: 3)

10.times do |i|
  log.info({ hello: "world", i: i })
end

