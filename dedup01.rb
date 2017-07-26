#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "1 inline worker (block_until_done)"

START = Time.now
# COLLECTOR_COUNT = 2   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes

class Collector < WorkerBase
  def run
    process_queue(true) do |msg| # NOTE: this is a true (non blocking)
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
  def initialize(n, db, f, c)
    super(n, db, f)
    @c = c
  end

  # server side filter
  def filter(_)
    true
  end

  def schedule
    @db.all.each do |rec|
      msg = {:id => rec.id, :queued => Time.now}
      if (t = rec.status)
        if filter(msg)
          @q.push(msg)
        else
          t = "X"
        end
        print t
      end
    end
  end

  def run
    run_loop(DURATION, INTERVAL) do
      old_sz = @q.size
      schedule
      print " q: #{old_sz}=>#{@q.size}\n#{SPACER}"
      @c.run
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
q.run_status
collectors.map(&:run_status)
db.run_status(START)
