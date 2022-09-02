require 'thread'

Thread::abort_on_exception = true
SPACER = " " * 13

# represents an AR database
# feel like the major flaw here is we do not dup the records
# In the meantime, please don't change inline but assign back into the db
# also ignored, implementation has more race conditions with data in transit
class Db
  def initialize(name)
    @mutex = Mutex.new
    @data = {}
    @writes = 0
    @reads = 0
    @name = name
  end

  def []=(n, v) ; @mutex.synchronize { @writes += 1 ; @data[n] = v } ; end
  def [](n)     ; @mutex.synchronize { @reads += 1 ; @data[n] } ; end
  def all
    @mutex.synchronize { @data.values } #.map(&:dup)
  end

  def size
    @mutex.synchronize { @data.size }
  end

  # this implementation assumes:
  # records not updated inline (not major if they are)
  # no read and write contention on same records
  def select(&block)
     @mutex.synchronize { @data.values }.select(&block).tap { |recs| @mutex.synchronize { @reads += recs.size } }
  end

  def run_status(*_)
    puts "#{@name} total writes: #{@writes}"
    puts "#{@name} total reads:  #{@reads}"
    if @data.first.last.respond_to?(:run_status)
      puts "#{@name} total refreshes: #{all.map(&:num_updates).sum}"
      all.each do |rec|
        puts rec.run_status
      end
    end
  end

  # sorry, but this was common across all and used while testing in irb
  # this is not thread safe (to avoid skewing the read/write counts)
  # 
  # every 3rd record is setup for realtime alerting
  def junk_data(record_count)
    record_count.times { |n|
      id = n
      @data[id] = Record.new(id, :alert => (n % 3 == 0))
    }
    self
  end
end

# this is a database record
class Record
  attr_accessor :last_updated, :id
  # [Boolean] true if this object has realtime alerts enabled
  attr_accessor :alert
  # table of updates
  attr_accessor :table

  def initialize(id, alert: false, last_updated: nil)
    @id = id
    @alert = alert
    @last_updated = last_updated
    @table = []
  end

  # implementation specific: different objects have different refresh schedules
  def status(dt = Time.now)
    if    last_updated.nil?                ; "N" # New:    always run
    elsif last_updated < (dt - 3) && alert ; "A" # Alert:  every  3 seconds
    elsif last_updated < (dt - 10)         ; "+" # Others: every 10 seconds
    end
  end

  # TODO: remove START constant pass in "time" (w/ subtracted START)
  def touch(dt = Time.now)
    @table << dt
    @last_updated = dt
    self
  end

  def num_updates
    @table.size
  end

  # TODO: remove START constant
  def run_status(*_)
    # times when this record was updated
    "vm#{"%02d" % id}: #{@table.map { |t| "%02d" % (t - START) }.join(" ")}"
  end
end

# Similar to Ruby thread.rb FIFO Queue
# The key difference is access to the data
# https://gist.github.com/ksss/2af768c068f4efcf3143
# https://github.com/bebac/thread-priority-queue/blob/master/lib/thread_priority_queue.rb
class Q
  def initialize
    @que = []
    @waiting = []
    @mutex = Mutex.new
    @count = 0
  end

  def push(obj)
    @mutex.synchronize do
      @count += 1
      @que.push(obj)
      begin
        t = @waiting.shift
        t.wakeup if t
      rescue ThreadError
        retry
      end
    end
  end

  def pop(blocking = true)
    @mutex.synchronize do
      while true
        if @que.empty?
          if blocking
            @waiting.push Thread.current
            @mutex.sleep
          else
            raise ThreadError, "queue empty"
          end
        else
          return @que.shift
        end
      end
    end
  end

  # We implemented this queue class so we could
  # add this one method
  # otherwise thread / queue would have been faster
  def find(h)
    @mutex.synchronize do
      @que.detect { |x| x[:id] == h[:id] }
    end
  end

  def size
    @que.size
  end

  def empty?
    @que.empty?
  end

  def run_status(*_)
    puts "q processed #{@count} messages"
  end
end

class WorkerBase
  attr_accessor :my_n, :processed, :skipped, :q, :db
  def initialize(my_n, db, q)
    @my_n, @q, @db = my_n, q, db
    @processed = @skipped = 0
  end

  # consumer
  def process_queue(blocking: true)
    while (msg = @q.pop(blocking) rescue nil) do
      if yield(msg)
        print "."
        @processed += 1
      else
        @skipped += 1
        print "x"
      end
    end
  end

  # used by coordinator to wait for the work to be completed
  # before starting another round
  def block_until_done
    while !@q.empty?
      printlnq_with_time("WAIT")
      sleep(1)
    end
  end

  # timer / scheduler (usually for the producer)
  # yield returns true to continue looping, else false
  # @param [Integer] interval how frequently to each collection run
  #                           hopefully how long each collection takes
  # @kwarg [Integer] duration how long to run experiment
  #                           if not provided, result from the work block is used
  # @kwarg [Block] feedback 
  # @yield work to perform
  #        if duration is not provided, block result is true: loop again, false: done
  def run_loop(interval, duration: nil, feedback: nil)
    # run the experiment for duration given
    stop = Time.now + duration if duration
    feedback ||= -> (time_took, interval) {
      extra = interval - time_took
      print_with_time "OVER BY #{"%.3f" % -extra} q=#{@q.size}" if extra < -0.01
    }

    print_with_time("START")
    loop do
      start = Time.now
      old_sz = @q.size
      # starting batch of work
      print_with_time("WORK")
      has_more_work = yield
      has_more_work = (start < stop) if stop
      new_sz = @q.size
      if new_sz != old_sz
        # we are either falling behind or getting ahead.
        print " q: #{old_sz}=>#{new_sz}\n#{SPACER}"
      else
        print "\n#{SPACER}"
      end
      time_took = Time.now - start
      feedback.call(time_took, interval)
      break unless has_more_work
      sleep(interval - time_took) if time_took < interval
    end
    # done with this experiment
    printlnq_with_time("DONE")
    self
  end

  def printlnq_with_time(message)
    print_with_time("#{message} q=#{@q.size}\n#{SPACER}")
  end

  def print_with_time(message)
    print "\n#{(Time.now - START.utc.to_i).strftime("%M:%S")} #{@my_n} #{message} "
  end

  # summary details
  def run_status(*_)
    if @skipped != 0
      puts "c#{@my_n}: processed #{@processed}/#{@processed+@skipped}"
    else
      puts "c#{@my_n}: processed #{@processed}"
    end
  end
end
