module Recurrent
  class Scheduler

    attr_accessor :tasks
    attr_reader :identifier

    def initialize(task_file=nil)
      @tasks = []
      @identifier = "host:#{Socket.gethostname} pid:#{Process.pid}" rescue "pid:#{Process.pid}"
      eval(File.read(task_file)) if task_file
    end

    def configure
      Configuration
    end

    def execute
      log "Starting Recurrent"

      trap('TERM') { log 'Exiting...'; $exit = true }
      trap('INT')  { log 'Exiting...'; $exit = true }
      trap('QUIT') { log 'Exiting...'; $exit = true }

      loop do
        execute_at = next_task_time
        tasks_to_execute = tasks_at_time(execute_at)

        until execute_at.past?
          sleep(0.5) unless $exit
        end

        break if $exit

        tasks_to_execute.each do |task|
          Thread.new do
            task.action.call
          end
        end

        break if $exit
      end
    end

    def every(frequency, key, options={}, &block)
      log("Adding Task: #{key}")
      @tasks << Task.new(:name => key,
                         :schedule => create_schedule(key, frequency, options[:start_time]),
                         :action => block)
    end

    def log(message)
      message = log_message(message)
      puts message
      Configuration.logger.call(message) if Configuration.logger
    end

    def log_message(message)
      "[Recurrent Scheduler: #{@identifier}] - #{message}"
    end

    def next_task_time
      @tasks.map { |task| task.next_occurrence }.sort.first
    end

    def tasks_at_time(time)
      tasks.select do |task|
        task.next_occurrence == time
      end
    end

    def create_rule_from_frequency(frequency)
      log("Creating an IceCube Rule")
      case frequency.inspect
      when /year/
        log("Creating a yearly rule")
        IceCube::Rule.yearly(frequency / 1.year)
      when /month/
        log("Creating a monthly rule")
        IceCube::Rule.monthly(frequency / 1.month)
      when /day/
        if ((frequency / 1.week).is_a? Integer) && ((frequency / 1.week) != 0)
          log("Creating a weekly rule")
          IceCube::Rule.weekly(frequency / 1.week)
        else
          log("Creating a daily rule")
          IceCube::Rule.daily(frequency / 1.day)
        end
      else
        if ((frequency / 1.hour).is_a? Integer) && ((frequency / 1.hour) != 0)
          log("Creating an hourly rule")
          IceCube::Rule.hourly(frequency / 1.hour)
        elsif ((frequency / 1.minute).is_a? Integer) && ((frequency / 1.minute) != 0)
            log("Creating a minutely rule")
            IceCube::Rule.minutely(frequency / 1.minute)
        else
          log("Creating a secondly rule")
          IceCube::Rule.secondly(frequency)
        end
      end
    end

    def create_schedule(name, frequency, start_time=nil)
      log("Creating schedule for: #{name}")
      if frequency.is_a? IceCube::Rule
        log("Frequency is an IceCube Rule: #{frequency.to_s}")
        rule = frequency
        frequency_in_seconds = rule.frequency_in_seconds
      else
        log("Frequency is an integer: #{frequency}")
        rule = create_rule_from_frequency(frequency)
        log("IceCube Rule created: #{rule.to_s}")
        frequency_in_seconds = frequency
      end
      start_time ||= derive_start_time(name, frequency_in_seconds)
      schedule = IceCube::Schedule.new(start_time)
      schedule.add_recurrence_rule rule
      log("schedule created for #{name}")
      schedule
    end

    def derive_start_time(name, frequency)
      log("No start time provided, deriving one.")
      if Configuration.load_task_schedule
        log("Attempting to derive from saved schedule")
        derive_start_time_from_saved_schedule(name, frequency)
      else
        derive_start_time_from_frequency(frequency)
      end
    end

    def derive_start_time_from_saved_schedule(name, frequency)
      saved_schedule = Configuration.load_task_schedule.call(name)
      if saved_schedule
        log("Saved schedule found for #{name}")
        saved_schedule = IceCube::Schedule.from_yaml(saved_schedule)
        if saved_schedule.frequency_in_seconds == frequency
          log("Saved schedule frequency matches, setting start time to saved schedules next occurrence: #{saved_schedule.next_occurrence.to_s(:seconds)}")
          saved_schedule.next_occurrence
        else
          log("Schedule frequency does not match saved schedule frequency")
          derive_start_time_from_frequency(frequency)
        end
      else
        derive_start_time_from_frequency(frequency)
      end
    end

    def derive_start_time_from_frequency(frequency)
      log("Deriving start time from frequency")
      current_time = Time.now
      if frequency < 1.minute
        log("Setting start time to beginning of current minute")
        current_time.change(:sec => 0, :usec => 0)
      elsif frequency < 1.hour
        log("Setting start time to beginning of current hour")
        current_time.change(:min => 0, :sec => 0, :usec => 0)
      elsif frequency < 1.day
        log("Setting start time to beginning of current day")
        current_time.beginning_of_day
      elsif frequency < 1.week
        log("Setting start time to beginning of current week")
        current_time.beginning_of_week
      elsif frequency < 1.month
        log("Setting start time to beginning of current month")
        current_time.beginning_of_month
      elsif frequency < 1.year
        log("Setting start time to beginning of current year")
        current_time.beginning_of_year
      end
    end
  end
end
