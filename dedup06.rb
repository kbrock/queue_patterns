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

class Collector < WorkerBase
  def initialize(my_n, db, filter)
    super(my_n, db, [])
    self.filter = filter
  end

  def filter=(value)
    @filter = text_to_block(value)
  end

  def process_mine
    @db.select(&@filter).each do |rec|
      if (t = rec.status)
        process(rec)
        print t
        @processed += 1
      end
    end
    true
  end

  # basically Collector#run
  def run
    run_loop(INTERVAL, duration: DURATION) do
      process_mine
    end
  end

  def process(record) # record is passed in
    sleep DELAY
    @db[record.id] = record.touch # save
  end

  # filter: "type;mod%val" (may want starting id)
  # future filter may include ems_id and object types
  def text_to_block(txt)
    if txt.nil?
      nil
    elsif txt.include?("%")
      mod, val = txt.split("%")
      mod = mod.to_i
      val = val.to_i
      Proc.new { |r| r.id % mod == val }
    else
      raise "bad filter"
    end
  end
end

db = Db.new("pg").junk_data(RECORD_COUNT)
collectors = COLLECTOR_COUNT.times.map do |n|
  Collector.new(n, db, "#{COLLECTOR_COUNT}%#{n}")
end
threads = collectors.map { |c| sleep(0.1) ; Thread.new() { c.run } }

threads.each{ |t| t.join }
puts
(collectors + [db]).map(&:run_status)
