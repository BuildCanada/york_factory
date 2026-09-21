require "open3"
require "timeout"

module Warehouse
  module Broadcasts
    class Command
      Result = Data.define(:stdout, :stderr, :status) do
        def success?
          status.success?
        end
      end

      class Error < StandardError
        attr_reader :argv, :result

        def initialize(message, argv:, result: nil)
          @argv = argv
          @result = result
          super(message)
        end
      end

      class Failed < Error; end
      class TimedOut < Error; end

      DEFAULT_TIMEOUT = 5.minutes
      DEFAULT_OUTPUT_LIMIT = 1.megabyte

      def initialize(timeout: DEFAULT_TIMEOUT, output_limit: DEFAULT_OUTPUT_LIMIT, environment: {})
        @timeout = timeout
        @output_limit = output_limit
        @environment = environment
      end

      # Executes argv directly. It intentionally does not accept a shell command string.
      # Output is drained completely to prevent a child process deadlock, while retained
      # output is capped so a noisy ffmpeg process cannot consume unbounded memory.
      def run(*argv, stdin_data: nil, allow_failure: false)
        argv = argv.flatten.map(&:to_s)
        raise ArgumentError, "command argv cannot be empty" if argv.empty?

        result = execute(argv, stdin_data:)
        if !allow_failure && !result.success?
          raise Failed.new(
            "command failed (#{result.status.exitstatus}): #{summary(result.stderr)}",
            argv:,
            result:
          )
        end
        result
      rescue Timeout::Error
        terminate_process_group(@pid)
        raise TimedOut.new("command exceeded #{@timeout} seconds", argv:)
      ensure
        @pid = nil
      end

      private

      def execute(argv, stdin_data:)
        stdout_text = stderr_text = nil
        status = nil

        Open3.popen3(@environment, *argv, pgroup: true) do |stdin, stdout, stderr, wait_thread|
          @pid = wait_thread.pid
          stdout_reader = Thread.new { read_bounded(stdout) }
          stderr_reader = Thread.new { read_bounded(stderr) }

          begin
            Timeout.timeout(@timeout) do
              begin
                stdin.binmode
                stdin.write(stdin_data) if stdin_data
              ensure
                stdin.close
              end

              stdout_text = stdout_reader.value
              stderr_text = stderr_reader.value
              status = wait_thread.value
            end
          rescue Timeout::Error
            terminate_process_group(@pid)
            stdout_reader.join
            stderr_reader.join
            raise
          ensure
            stdin.close unless stdin.closed?
            stdout.close unless stdout.closed?
            stderr.close unless stderr.closed?
          end
        end

        Result.new(stdout: stdout_text, stderr: stderr_text, status:)
      end

      def read_bounded(io)
        io.binmode
        retained = +"".b
        while (chunk = io.read(16.kilobytes))
          remaining = @output_limit - retained.bytesize
          retained << chunk.byteslice(0, remaining) if remaining.positive?
        end
        retained.force_encoding(Encoding::UTF_8).scrub
      end

      def terminate_process_group(pid)
        return unless pid

        Process.kill("TERM", -pid)
        sleep 0.1
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
        nil
      end

      def summary(stderr)
        stderr.to_s.lines.last(8).join.strip.presence || "no diagnostic output"
      end
    end
  end
end
