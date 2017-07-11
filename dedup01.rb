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
  end

  def run
    while (msg = @q.pop(true) rescue nil) do # *** special code of interest
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
      @q.push(msg) if t
      print t # || (Time.now - lu).to_i
    end
  end
  def block_until_done # *** special code of interest
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
      Collector.new(1, @db, @q).run # *** special code of interest
      block_until_done # *** special code of interest
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

coordinator.run.block_until_done
db.run_status(START)
q.run_status
