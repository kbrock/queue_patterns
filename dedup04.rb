#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "client filter on date of last processed"

START = Time.now
COLLECTOR_COUNT = 2   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes
PADDING         = 3   # assume task runs every 3 seconds or longer

class Collector < WorkerBase
  def initialize(my_n, db, q, timestamps)
    super(my_n, db, q)
    @timestamps = timestamps
  end

  def run
    process_queue do |msg|
      filter(msg) && process(msg)
    end
  end

  # client side filter
  def filter(msg)
    id = msg[:id]
    dt = msg[:queued]
    previous_run = @timestamps[id]
    if previous_run.nil? || previous_run < dt
      new_dt = Time.now + PADDING
      @timestamps[id] = new_dt # new value for previous_run
      true
    else
      false
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
        @q.push(msg)
        print t
        @processed += 1
      end
    end
    true
  end

  def run
    run_loop(INTERVAL, duration: DURATION) do
      schedule
    end
    self
  end
end

db = Db.new("pg").junk_data(RECORD_COUNT)

q = Q.new
timestamps = Db.new("redis")
coordinator = Coordinator.new("C", db, q)
collectors = COLLECTOR_COUNT.times.map do |n|
  Collector.new(n, db, q, timestamps)
end
threads = collectors.map { |c| sleep(0.1) ; Thread.new() { c.run } }

coordinator.run.block_until_done
puts
([coordinator, q] + collectors + [timestamps, db]).map(&:run_status)
