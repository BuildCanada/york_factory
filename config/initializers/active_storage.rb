# Cloudflare R2 does not support multiple checksum algorithms in a single request.
# Newer versions of aws-sdk-s3 (>= 1.175) send checksums by default, which causes
# "You can only specify one non-default checksum at a time" errors on upload.
Aws.config.update(
  request_checksum_calculation: "when_required",
  response_checksum_validation: "when_required"
)
