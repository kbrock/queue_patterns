require 'thread'

Thread::abort_on_exception = true
SPACER          = "             "

# represents an AR database
# feel like the major flaw here is we do not dup the records
# In the meantime, please don't change inline but assign back into the db
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

  def run_status(start)
    puts "#{@name} total writes: #{@writes}"
    puts "#{@name} total reads:  #{@reads}"
    if @data.first.last.respond_to?(:run_status)
      puts "#{@name} total refreshes: #{all.map { |rec| rec.table.size }.inject(&:+)}"
      all.each do |rec|
        puts rec.run_status(start)
      end
    end
  end

  # sorry, but this was common across all and used while testing in irb
  def junk_data(record_count)
    record_count.times { |n|
      id = n
      self[id] = Record.new(id, n % 3 == 0)
    }
    self
  end
end

# this is a database record
class Record
  attr_accessor :last_updated, :id, :alert, :table
  def initialize(id, alert = false, last_updated = nil)
    @id = id
    @alert = alert
    @last_updated = last_updated
    @table = []
  end

  def status(dt = Time.now)
    if    last_updated.nil?                ; "N" # New:    always run
    elsif last_updated < (dt - 3) && alert ; "A" # Alert:  every  3 seconds
    elsif last_updated < (dt - 10)         ; "+" # Others: every 10 seconds
    end
  end

  def touch(dt = Time.now)
    @table << dt
    @last_updated = dt
    self
  end

  def run_status(start)
    "vm#{"%02d" % id}: #{@table.map { |t| "%02d" % (t - start) }.join(" ")}"
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

  def pop(non_block = false)
    @mutex.synchronize do
      while true
        if @que.empty?
          raise ThreadError, "queue empty" if non_block
          @waiting.push Thread.current
          @mutex.sleep
        else
          return @que.shift
        end
      end
    end
  end

  # We implemented queue so we could
  # add this method
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
  def process_queue(non_blocking = false)
    while (msg = @q.pop(non_blocking) rescue nil) do
      if yield(msg)
        print "."
        @processed += 1
      else
        @skipped += 1
        print "x"
      end
    end
  end

  def block_until_done
    while !@q.empty?
      print "\n00:#{"%02d" % (Time.now - START)} #{@my_n} WAIT q=#{@q.size}\n#{SPACER}"
      sleep(1)
    end
  end

  # timer / scheduler (usually for the producer)
  def run_loop(duration, interval)
    stop = Time.now + duration
    begin
      start = Time.now
      old_sz = @q.size
      print "\n00:#{"%02d" % (Time.now - START)} #{@my_n} WORK "
      yield
      new_sz = @q.size
      if new_sz != old_sz
        print " q: #{old_sz}=>#{new_sz}\n#{SPACER}"
      else
        print "\n#{SPACER}"
      end
      sleep_time = interval - (Time.now - start)
      if sleep_time < 0
        if sleep_time < -0.01
          print "\n00:#{"%02d" % (Time.now - START)} #{@my_n} OVER BY #{"%.3f" % -sleep_time} q=#{@q.size}"
        end
        # print SPACER
      else
        sleep(sleep_time)
      end
    end until (start > stop)
    print "\n00:#{"%02d" % (Time.now - START)} #{@my_n} DONE q=#{@q.size}\n#{SPACER}"
    self
  end

  # summary details
  def run_status(*_)
    if @skipped != 0
      puts "c#{@my_n}: #{@processed}/#{@processed+@skipped}"
    else
      puts "c#{@my_n}: #{@processed}"
    end
  end
end
