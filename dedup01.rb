#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "1 inline worker (block_until_done)"

# this is a simple single threaded metrics collection
# since RECORD_COUNT * DURATION > INTERVAL, this system is overloaded.

# implemented as 2 phases: determine all work, process all work
# so process all work is non-blocking and bails when no work is outstanding.

START = Time.now
# COLLECTOR_COUNT = 1   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes

class Collector < WorkerBase
  def run
    process_queue(blocking: false) do |msg|
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
  def initialize(n, db, f, collector)
    super(n, db, f)
    @collector = collector
  end

  def schedule
    @db.all.each do |rec|
      msg = {:id => rec.id, :queued => Time.now}
      if (t = rec.status)
        @processed += 1
        @q.push(msg)
        print t
      end
    end
  end

  def run
    run_loop(INTERVAL, duration: DURATION) do
      old_sz = @q.size
      schedule
      print " q: #{old_sz}=>#{@q.size}\n#{SPACER}"
      # this is single threaded
      # so we process all the work before we are done
      # this is the only experiment that does this
      @collector.run
      true
    end
  end
end

db = Db.new("pg").junk_data(RECORD_COUNT)

q = Q.new
collectors = 1.times.map do |n|
  Collector.new(n, db, q)
end
coordinator = Coordinator.new("C", db, q, collectors.first)

coordinator.run.block_until_done
puts
([coordinator, q] + collectors + [db]).map(&:run_status)
