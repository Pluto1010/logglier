$:.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'logglier'

#url = "http://logs-01.loggly.com/bulk/TOKEN/tag/bulk/"
url = "http://requestb.in/1m3t2p51"

log = Logglier.new(url, threaded: true, bulk: true, format: :json, bulk_max_size: 10)

11.times do |i|
  log.info({ hello: "world", i: i })
end
