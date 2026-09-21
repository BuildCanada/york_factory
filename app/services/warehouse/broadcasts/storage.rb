require "stringio"

module Warehouse::Broadcasts
  # Source media never goes through the application's ActiveStorage bucket.
  class Storage
    def initialize(client: nil, bucket: nil)
      if !client && ENV["BROADCAST_STORAGE_SERVICE"] == "local_archive"
        raise ArgumentError, "local archive storage is only available in development or test" unless Rails.env.development? || Rails.env.test?

        @disk = ActiveStorage::Blob.services.fetch("local_archive")
        return
      end
      configuration = client ? {} : Rails.application.credentials.r2.to_h
      @bucket = bucket || ENV["R2_BUCKET"].presence || configuration.fetch(:bucket)
      @client = client || Aws::S3::Client.new(
        region: "auto",
        endpoint: ENV["R2_ENDPOINT"].presence || configuration.fetch(:endpoint),
        access_key_id: ENV["R2_ACCESS_KEY_ID"].presence || configuration.fetch(:access_key_id),
        secret_access_key: ENV["R2_SECRET_ACCESS_KEY"].presence || configuration.fetch(:secret_access_key),
        force_path_style: true,
        retry_limit: 2,
        http_open_timeout: 10,
        http_read_timeout: 60
      )
    end

    def upload(key:, body:, content_type: "application/octet-stream")
      return @disk.upload(key, body.respond_to?(:read) ? body : StringIO.new(body)) if @disk

      @client.put_object(bucket: @bucket, key: key, body: body, content_type: content_type)
    end

    def download(key:)
      return @disk.download(key) if @disk

      @client.get_object(bucket: @bucket, key: key).body.read
    end

    def download_to(key:, path:)
      if @disk
        File.open(path, "wb") { |file| @disk.download(key) { |chunk| file.write(chunk) } }
      else
        @client.get_object(bucket: @bucket, key: key, response_target: path)
      end
    end

    def url(key:, expires_in: 900)
      if @disk
        return ActiveStorage::Current.set(url_options: Rails.application.routes.default_url_options) do
          @disk.url(key, expires_in:, disposition: :inline,
            filename: ActiveStorage::Filename.new(File.basename(key)), content_type: "video/mp2t")
        end
      end
      Aws::S3::Presigner.new(client: @client).presigned_url(
        :get_object, bucket: @bucket, key: key, expires_in: expires_in
      )
    end
  end
end
