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

class Collector # worker
  def initialize(my_n) ; @my_n = my_n ; end
  def run(q, db)
    while (msg = q.pop(false) rescue nil) do
      process(msg, db)
      # q.ack(msg)
      print "."
    end
  end

  def process(msg, db)
    record = db[msg[:id]]       # find
    sleep DELAY # rand(0)       # work TODO: add hang or exception
    db[msg[:id]] = record.touch # save
  end
end

class Coordinator # producer
  def initialize(db, q)
    @db = db
    @q = q
  end

  def schedule
    puts "", "W (#{@q.size}) #{@q.empty? ? "" : "WARNING non empty queue"}"
    @db.all.each do |rec|
      t = rec.status
      msg = {:id => rec.id}
      @q.push(msg) if t
      print t # || (Time.now - lu).to_i
    end
  end
  def block_until_done # *** special code of interest
    while !@q.empty?
      puts "", "Q (#{@q.size})"
      sleep(1)
    end
  end
  def run
    stop = Time.now + DURATION
    begin
      start = Time.now
      schedule
      block_until_done # *** special code of interest
      sleep([INTERVAL - (Time.now - start), 0].max.round)
    end until (start > stop)
    puts "", "D (#{@q.size}) DONE"
  end
end

db = Db.new
RECORD_COUNT.times { |n|
  db["vm#{n}"] = Record.new("vm#{n}", n % 3 == 0)
}

q = Q.new
coordinator = Coordinator.new(db, q)
collectors = COLLECTOR_COUNT.times.map do |n|
  Thread.new(n+1) do |my_n|
    Collector.new(my_n).run(q, db)
  end
end

coordinator.run
db.run_status(START)
