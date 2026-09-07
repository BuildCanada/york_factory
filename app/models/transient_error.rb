require "time"

class TransientError < StandardError
  attr_reader :retry_after, :status

  def self.retry_after_seconds(value, now: Time.current)
    return if value.blank?

    seconds = Integer(value, exception: false)
    return seconds if seconds && seconds >= 0

    delay = Time.httpdate(value.to_s) - now
    delay.ceil if delay.positive?
  rescue ArgumentError
    nil
  end

  def initialize(message = nil, retry_after: nil, status: nil)
    @retry_after = retry_after
    @status = status
    super(message)
  end
end
