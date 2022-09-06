#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "worker dynamic workload ENV"

START = Time.now
COLLECTOR_COUNT = 2   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes
PADDING         = 3 # assume task runs every 3 (or takes 3)

class Supervisor # < WorkerBase
  attr_accessor :count
  def initialize(db)
    @id = 0
    @db = db
    @threads = []
    @collectors = []
    # collectors that have been removed
    # keep around stale to print final statistics
    @stale = []
  end

  def count=(count)
    current_count = @collectors.count
    chopping_block = []
    if count > current_count # increase collectors
      # re-assign the filters
      @collectors.each_with_index { |c, n| c.filter = "#{count}%#{n}" }
      current_count.upto(count - 1) do |n|
        c = Collector.new(@id += 1 -1, @db, "#{count}%#{n}")
        @collectors << c
        sleep(0.1) # just for demo display
        @threads << Thread.new { c.run }
      end
    elsif count < current_count # reduce collectors
      count.upto(current_count - 1) do |i|
        c = @collectors.shift
        c.filter = nil # ask filter to exit (after work is done)
        @stale << c
        chopping_block << @threads.shift
      end
      @collectors.each_with_index { |c, n| c.filter = "#{count}%#{n}" }
    end
    @count = count
    # wait for the completed threads to finish
    # in the base of the script, this blocks until all work is done (via s.count = 0)
    chopping_block.each { |t| t.join }
  end

  def run_status
    @stale.map(&:run_status)
    @collectors.map(&:run_status) # should have none of these
  end
end

class Collector < WorkerBase
  def initialize(my_n, db, filter = nil)
    super(my_n, db, [])
    self.filter = filter
  end

  def filter=(value)
    @filter = text_to_block(value)
  end

  def done?
    @filter.nil?
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
    run_loop(INTERVAL) do
      break if done? # not sure if this should be a pre or post condition
      process_mine
      !done?
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
s = Supervisor.new(db)
s.count = COLLECTOR_COUNT
sleep(DURATION)
s.count = 0 # this will kill off all collectors
puts
# collectors are part of the supervisor - no need to calculate
([s] + [db]).map(&:run_status)
