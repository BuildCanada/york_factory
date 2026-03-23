class R2Storage
  def initialize
    @client = Aws::S3::Client.new(
      region: "auto",
      endpoint: ENV.fetch("R2_ENDPOINT"),
      access_key_id: ENV.fetch("R2_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
      force_path_style: true
    )
    @bucket = ENV.fetch("R2_BUCKET")
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
