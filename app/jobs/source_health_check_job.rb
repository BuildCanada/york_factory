class SourceHealthCheckJob < ApplicationJob
  queue_as :default

  def perform
    Source.find_each do |source|
      check_source(source)
    end
  end

  private

  def check_source(source)
    response = HTTPX.head(source.url)

    unless (200..399).include?(response.status)
      Rails.logger.error "[HealthCheck] Source #{source.name} returned HTTP #{response.status}: #{source.url}"
    end
  rescue => e
    Rails.logger.error "[HealthCheck] Source #{source.name} unreachable: #{e.message}"
  end
end
