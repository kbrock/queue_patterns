#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "put_unless_exists"

START = Time.now
COLLECTOR_COUNT = 2   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes

class Collector # worker
  def initialize(my_n, db, q)
    @my_n, @q, @db = my_n, q, db
  end

  def run
    while (msg = @q.pop(false) rescue nil) do
      process(msg)
      # @q.ack(msg)
      print "."
    end
  end

  def process(msg)
    record = @db[msg[:id]]       # find
    sleep DELAY # rand(0)        # work TODO: add hang or exception
    @db[msg[:id]] = record.touch # save
  end
end

class Coordinator # producer
  def initialize(db, q)
    @db, @q = db, q
  end

  def schedule
    puts "", "00:#{"%02d" % (Time.now - START)} WORK q=#{@q.size} #{@q.empty? ? "" : "WARNING non empty queue"}"
    @db.all.each do |rec|
      t = rec.status
      msg = {:id => rec.id}
      if t
        # this is the core of put_unless_exists
        if @q.find(msg) # *** special code of interest
          t = "X"
        else
          @q.push(msg)
        end
        print t
      end
    end
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

db = Db.new
RECORD_COUNT.times { |n|
  id = "vm#{"%02d" % n}"
  db[id] = Record.new(id, n % 3 == 0)
}

q = Q.new
coordinator = Coordinator.new(db, q)
collectors = COLLECTOR_COUNT.times.map do |n|
  Thread.new(n+1) do |my_n|
    Collector.new(my_n, db, q).run
  end
end

coordinator.run.block_until_done
db.run_status(START)
q.run_status
