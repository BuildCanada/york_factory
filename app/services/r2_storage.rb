class R2Storage
  def initialize
    r2 = Rails.application.credentials.r2
    @client = Aws::S3::Client.new(
      region: "auto",
      endpoint: r2.fetch(:endpoint),
      access_key_id: r2.fetch(:access_key_id),
      secret_access_key: r2.fetch(:secret_access_key),
      force_path_style: true
    )
    @bucket = r2.fetch(:bucket)
  end

  def upload(key:, body:)
    @client.put_object(bucket: @bucket, key: key, body: body)
  end

  def download(key:)
    @client.get_object(bucket: @bucket, key: key).body.read
  end

  def exists?(key:)
    @client.head_object(bucket: @bucket, key: key)
    true
  rescue Aws::S3::Errors::NotFound
    false
  end
end
