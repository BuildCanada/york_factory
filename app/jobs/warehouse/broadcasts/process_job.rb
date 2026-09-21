module Warehouse
  module Broadcasts
    class ProcessJob < ApplicationJob
      queue_as :default
      limits_concurrency to: 1,
        key: ->(media_stream_id) { "broadcast-process-#{media_stream_id}" },
        duration: 30.minutes,
        on_conflict: :discard

      retry_on Warehouse::Broadcasts::Command::TimedOut, wait: :polynomially_longer, attempts: 4

      def perform(media_stream_id)
        stream = Warehouse::MediaStream.find(media_stream_id)
        processor = Processor.new(stream)
        processor.call
        BacklogJob.set(wait: 1.second).perform_later(media_stream_id) if processor.more_work?
      end

      # This indirection schedules the next bounded batch after the current
      # ProcessJob has released its concurrency semaphore.
      class BacklogJob < ApplicationJob
        queue_as :default

        def perform(media_stream_id)
          ProcessJob.perform_later(media_stream_id)
        end
      end
    end
  end
end
