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

class Collector # worker
  def initialize(my_n, db, q)
    @my_n, @q, @db = my_n, q, db
    @processed = 0
  end

  def run
    while (msg = @q.pop(true) rescue nil) do # *** special code of interest
      if true # client side filtering would go here
        process(msg)
        print "."
        @processed += 1
      end
    end
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
  def initialize(db, q, c)
    @db, @q, @c= db, q, c
  end

  def schedule
    puts
    old_sz = @q.size
    print "00:#{"%02d" % (Time.now - START)} WORK "
    @db.all.each do |rec|
      t = rec.status
      msg = {:id => rec.id, :queued => Time.now}
      if t
        if true # client filter would go here
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
      print "           "
      sleep(1)
    end
  end
  def run
    stop = Time.now + DURATION
    begin
      start = Time.now
      schedule
      @c.run # *** special code of interest
      sleep([INTERVAL - (Time.now - start), 0].max.round)
    end until (start > stop)
    puts "", "00:#{"%02d" % (Time.now - START)} DONE q=#{@q.size}"
    self
  end
end

db = Db.new("pg")
RECORD_COUNT.times { |n|
  id = "vm#{"%02d" % n}"
  db[id] = Record.new(id, n % 3 == 0)
}

q = Q.new
c = Collector.new(1, db, q) # *** special code of interest
collectors = [c]
coordinator = Coordinator.new(db, q, c)

coordinator.run.block_until_done
puts
q.run_status
collectors.map(&:run_status)
db.run_status(START)
