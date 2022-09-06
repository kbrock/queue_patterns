#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "block_until_done"

# this is the multi threaded simple version
# it produces all work then waits for all work to be done before starting again.
#   note the WAIT text and the queue size decreasing
# this waiting avoids race conditions

START = Time.now
COLLECTOR_COUNT = 2   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes

class Collector < WorkerBase
  def run
    process_queue do |msg|
      process(msg)
    end
  end

  def process(msg)
    record = @db[msg[:id]]
    sleep DELAY
    @db[record.id] = record.touch
    true
  end
end

class Coordinator < WorkerBase
  def schedule
    @db.all.each do |rec|
      msg = {:id => rec.id, :queued => Time.now}
      if (t = rec.status)
        @processed += 1
        @q.push(msg)
        print t
      end
    end
    true
  end

  def run
    run_loop(INTERVAL, duration: DURATION) do
      schedule
      # wait for all metrics to be collected before requesting more work
      block_until_done
      true
    end
    self
  end
end

db = Db.new("pg").junk_data(RECORD_COUNT)

q = Q.new
coordinator = Coordinator.new("C", db, q)
collectors = COLLECTOR_COUNT.times.map do |n|
  Collector.new(n, db, q)
end
threads = collectors.map { |c| sleep(0.1) ; Thread.new() { c.run } }

coordinator.run.block_until_done
puts
([coordinator, q] + collectors + [db]).map(&:run_status)
