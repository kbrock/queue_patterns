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
PADDING         = 3 # assume task runs every 3 (or takes 3)

class Collector # worker
  def initialize(my_n, db, q, filter)
    @my_n, @q, @db, @filter = my_n, q, db, filter
    @attempts = @processed = 0
  end

  def run
    while (msg = @q.pop(false) rescue nil) do
      filter(msg) do # *** special code of interest
        process(msg)
        print "."
        @processed += 1
      end
    end
  end

  # client side filter
  def filter(msg)
    id = msg[:id]
    dt = msg[:queued]
    previous_run = @filter[id]
    @attempts += 1
    if previous_run.nil? || previous_run < dt
      new_dt = Time.now + PADDING
      @filter[id] = new_dt
      yield
      # new_dt = Time.now #+ PADDING - 1 # -1? just use now?
      # @filter[id] = new_dt
    else
      print "x"
      false
    end
  end

  def process(msg)
    record = @db[msg[:id]]       # find
    sleep DELAY # rand(0)        # work TODO: add hang or exception
    @db[msg[:id]] = record.touch # save
  end

  def run_status(*_)
    puts "c#{@my_n}: #{@processed}/#{@attempts}"
  end
end

class Coordinator # producer
  def initialize(db, q)
    @db, @q = db, q
  end

  def schedule
    puts ""
    old_sz = @q.size
    print "00:#{"%02d" % (Time.now - START)} WORK "
    @db.all.each do |rec|
      t = rec.status
      msg = {:id => rec.id, :queued => Time.now}
      if t
        if true # producer filtering would go here
          @q.push(msg)
        end
        print t
      end
    end
    puts " q: #{old_sz}=>#{@q.size}"
    print "           "
  end

  def block_until_done
    while !@q.empty?
      puts "", "00:#{"%02d" % (Time.now - START)} WAIT q=#{@q.size}"
      sleep(1)
    end
  end

  def run
    stop = Time.now + DURATION
    begin
      start = Time.now
      schedule
      sleep([INTERVAL - (Time.now - start), 0].max.round)
    end until (start > stop)
    puts "", "00:#{"%02d" % (Time.now - START)} DONE q=#{@q.size}"
    self
  end
end

db = Db.new("pg").junk_data(RECORD_COUNT)

q = Q.new
filter = Db.new("redis")
coordinator = Coordinator.new(db, q)
collectors = COLLECTOR_COUNT.times.map do |n|
  c = Collector.new(n, db, q, filter)
  Thread.new(n+1) do
    c.run
  end
  c
end

coordinator.run.block_until_done
puts
q.run_status
collectors.map(&:run_status)
filter.run_status(START)
db.run_status(START)
