require 'thread'

# represents an AR database
# feel like the major flaw here is we do not dup the records
# In the meantime, please don't change inline but assign back into the db
class Db
  def initialize
    @mutex = Mutex.new
    @data = {}
    @writes = 0
    @reads = 0
  end
  def []=(n, v) ; @mutex.synchronize { @reads += 1 ; @data[n] = v } ; end
  def [](n)     ; @mutex.synchronize { @writes += 1 ; @data[n] } ; end
  def all
    @mutex.synchronize { @data.values } #.map(&:dup)
  end

  def run_status(start)
    puts "total writes: #{@writes}"
    puts "total reads:  #{@reads}"
    if @data.first.respond_to?(:run_status)
      all.each do |rec|
        puts rec.run_status(start)
      end
      puts "total refreshes: #{all.map { |rec| rec.table.size }.inject(&:+)}"
    end
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
    delta = @last_updated ? dt - @last_updated : nil
    @table << [dt, delta]
    @last_updated = dt
    self
  end

  def run_status(start)
    "#{id}: #{@table.map { |t| "%02d" % (t.first - start) }.join(" ")}"
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

  def run_status
    puts "processed #{@count} messages"
  end
end

class Red
  def initialize
    @data      = {}
    @padding   = 3 # amount of time to pad on record
    @attempts  = 0
    @processed = 0
  end

  # does this pass the filter
  def pass?(id, dt)
    previous_run = @data[id]
    @attempts += 1
    if previous_run.nil? || previous_run < dt
      @data[id] = Time.now + @padding
      true
    else
      false
    end
  end

  # mark this one as having been processed / reset it
  def mark(id)
    now = Time.now
    @data[id] = now + @padding - 1
    @processed += 1
  end

  def run_status
    puts "filter attempts #{@attempts}"
    puts "filter passed #{@processed}"
  end
end
