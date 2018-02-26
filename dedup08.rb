#!/usr/bin/env ruby
require 'thread'
require_relative 'common'

puts "worker dynamic workload http_filters"

START = Time.now
COLLECTOR_COUNT = 2   # number of collectors
RECORD_COUNT    = 100 # number of records in database
INTERVAL        = 2   # frequency of determining if there needs to be work
DURATION        = 20  # length of test
DELAY           = 0.1 # time each work item takes
PADDING         = 3 # assume task runs every 3 (or takes 3)

class Supervisor < WorkerBase
  # populated from descriptor
  attr_accessor :count
  def initialize
    super("S", nil, [])
    @filters = {}
    @mutex = Mutex.new
  end

  # event in k8s
  def collector_added(id)
    @filters[id] = ""
    assign_filters
    @filters[id]
  end

  # event in k8s
  def collector_removed(id)
    @filters.delete(id)
    assign_filters
  end

  # http request
  # could use config maps instead
  def get_filter(id)
    @filters[id]
  end

  # http request
  def finished_work(id, delta = nil, given = nil)
    if delta && delta < -0.01
      print_with_time "OVER BY #{"%.3f" % -delta}/#{given}"
    end
    if delta && delta > given/4 # 25% idle
      print_with_time "UNDER BY #{"%.3f" % delta}/#{given}"
    end
    # print SPACER
    # feedback mechanism
    # determine if we need more / fewer nodes
  end

  def count=(count)
    @count = count
    assign_filters
  end

  def assign_filters
    # need a better algorithm
    # choose non nil entries
    # attempt to produce same filter for same id if possible
    # not sure if we should set a nil to a filter (ask it to go away)
    #   or if that is the job for someone else
    @filters.keys.each_with_index do |id, i|
      if i <  count
        @filters[id] = "#{count}%#{i}"
      else # have too many clients, ask one to go away?
        @filters[id] = nil
      end
    end
  end
end

class Collector < WorkerBase
  attr_accessor :supervisor
  def initialize(my_n, db, s)
    super(my_n, db, [])
    @supervisor = s
  end

  def filter=(value)
    @filter = text_to_block(value)
  end

  # k8s signal
  def sig_quit
    @filter = nil
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
    supervisor.collector_added(@my_n)
    status_check = -> (actual_time) { supervisor.finished_work(@my_n, INTERVAL - actual_time, INTERVAL)}

    print_with_time("START")
    run_nice(INTERVAL, status_check) do
      self.filter = supervisor.get_filter(@my_n)
      !done? && process_mine
    end
    printlnq_with_time("DONE")

    supervisor.collector_removed(@my_n)
    self
  end

  def process(record) # record is passed in
    sleep DELAY
    @db[record.id] = record.touch # save
  end

  # filter: "mod%val"
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
s = Supervisor.new

# this will be read from descriptor
s.count = COLLECTOR_COUNT

collectors = COLLECTOR_COUNT.times.map do |n|
  Collector.new(n, db, s)
end
threads = collectors.map { |c| sleep(0.1) ; Thread.new() { c.run } }

sleep(DURATION)

s.count = 0
collectors.map(&:sig_quit)
threads.each{ |t| t.join }
puts

collectors.map(&:run_status)
db.run_status
