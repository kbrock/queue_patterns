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
SPACER          = "             "

class Collector # worker
  def initialize(my_n, db, q)
    @my_n, @q, @db = my_n, q, db
    @processed = 0
  end

  def run
    while (msg = @q.pop(false) rescue nil) do
      if filter(msg)
        process(msg)
        print "."
        @processed += 1
      else
        print "x"
      end
    end
  end

  # client side filter
  def filter(_)
    true
  end

  def process(msg)
    record = @db[msg[:id]]       # find
    sleep DELAY # rand(0)        # work TODO: add hang or exception
    @db[msg[:id]] = record.touch # save
  end

  def run_status(*_)
    puts "c#{@my_n}: #{@processed}"
  end
end

class Coordinator # producer
  def initialize(db, q)
    @my_n, @db, @q = "C", db, q
  end

  # server side filter
  def filter(_)
    true
  end

  def schedule
    puts
    old_sz = @q.size
    print "00:#{"%02d" % (Time.now - START)} #{@my_n} WORK "
    @db.all.each do |rec|
      t = rec.status
      msg = {:id => rec.id, :queued => Time.now}
      if t
        if filter(msg)
          @q.push(msg)
        else
          t = "X"
        end
        print t
      end
    end
    puts " q: #{old_sz}=>#{@q.size}"
    print SPACER
  end

  def block_until_done
    while !@q.empty?
      puts "", "00:#{"%02d" % (Time.now - START)} #{@my_n} WAIT q=#{@q.size}"
      print SPACER
      sleep(1)
    end
  end

  def run
    stop = Time.now + DURATION
    begin
      start = Time.now
      schedule
      block_until_done # *** special code of interest
      sleep_time = INTERVAL - (Time.now - start)
      if sleep_time < 0
        if sleep_time < 0.01
          puts
          print "00:#{"%02d" % (Time.now - START)} #{@my_n} OVER BY #{"%.2f" % -sleep_time} q=#{@q.size}"
        end
        # print SPACER
      else
        sleep(sleep_time)
      end
    end until (start > stop)
    puts "", "00:#{"%02d" % (Time.now - START)} #{@my_n} DONE q=#{@q.size}"
    self
  end
end

db = Db.new("pg").junk_data(RECORD_COUNT)

q = Q.new
coordinator = Coordinator.new(db, q)
collectors = COLLECTOR_COUNT.times.map do |n|
  Collector.new(n, db, q)
end
threads = collectors.map { |c| sleep(0.1) ; Thread.new() { c.run } }

coordinator.run.block_until_done
puts
q.run_status
collectors.map(&:run_status)
db.run_status(START)
