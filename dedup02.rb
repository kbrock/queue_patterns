#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "block_until_done"

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
    @db[msg[:id]] = record.touch
    true
  end
end

class Coordinator < WorkerBase
  def schedule
    @db.all.each do |rec|
      msg = {:id => rec.id, :queued => Time.now}
      if (t = rec.status)
        @q.push(msg)
        print t
      end
    end
  end

  def run
    run_loop(DURATION, INTERVAL) do
      schedule
      block_until_done
    end
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
q.run_status
collectors.map(&:run_status)
db.run_status(START)
