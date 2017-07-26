#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "worker static workload"

START = Time.now
COLLECTOR_COUNT = 2   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes
PADDING         = 3 # assume task runs every 3 (or takes 3)

class Collector # worker
  def initialize(my_n, db, &block)
    @my_n, @db = my_n, db
    # predetermined work to be done
    @filter = block
    @processed = 0
  end

  # basically Collector#schedule
  def process_msg
    puts
    print "00:#{"%02d" % (Time.now - START)} WORK "
    @db.select(&@filter).each do |rec|
      t = rec.status
      if t
        process(rec)
        print t
        # print @my_n
        @processed += 1
      end
    end
  end

  # basically Collector#run
  def run
    stop = Time.now + DURATION
    loop do
      start = Time.now
      process_msg
      break if start > stop

      sleep_time = INTERVAL - (Time.now - start)
      if sleep_time < 0
        puts
        puts "00:#{"%02d" % (Time.now - START)} OVER w=#{@my_n} [#{-sleep_time}]"
        print "           "
      else
        sleep(sleep_time)
      end
    end
    puts "", "00:#{"%02d" % (Time.now - START)} DONE w=#{@my_n}"
    print "           "
    self
  end

  def process(record) # record is passed in
    sleep DELAY
    @db[record.id] = record.touch # save
  end

  def run_status(*_)
    puts "c#{@my_n}: #{@processed}"
  end
end

class Coordinator # producer
  def initialize(db, q, filter)
    @db, @q, @filter = db, q, filter
  end

  # server side filter
  def filter(msg)
    id = msg[:id]
    dt = msg[:queued]
    previous_run = @filter[id]
    if previous_run.nil? || previous_run < dt
      new_dt = Time.now + PADDING
      @filter[id] = new_dt # new value for previous_run
      true
    else
      false
    end
  end

  def schedule
    puts
    old_sz = @q.size
    print "00:#{"%02d" % (Time.now - START)} WORK "
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
    print "           "
  end

  def block_until_done
    while !@q.empty?
      puts "", "00:#{"%02d" % (Time.now - START)} WAIT q=#{@q.size}"
      print "           "
      sleep(1)
    end
  end
end

db = Db.new("pg").junk_data(RECORD_COUNT)
collectors = COLLECTOR_COUNT.times.map do |n|
  Collector.new(n, db) { |r| r.id % COLLECTOR_COUNT == n }
end
threads = collectors.map { |c| sleep(0.1) ; Thread.new() { c.run } }

threads.each{ |t| t.join }
puts
collectors.map(&:run_status)
db.run_status(START)
