require "json_schemer"

# Integration tests for the public data API (/v1). Every response a test
# checks is validated against the OpenAPI contract with json_schemer: the
# status must be one the operation declares, the body must match that
# response's schema, and each header the contract declares must match its
# schema when present (RateLimit, ETag and friends).
class PublicApiTestCase < ActionDispatch::IntegrationTest
  include FactFactoryApiFixtures

  setup do
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/controllers/public_api"))
    PublicApi::RateLimiter.store = ActiveSupport::Cache::MemoryStore.new
    FactFactory::ReleaseQuery.reset!
    FactFactory::DatasetQuery.reset!
    FactFactory::SearchQuery.reset!
  end

  teardown { PublicApi::RateLimiter.reset_store! }

  # Always-present headers of a 200 (the contract's conventions, README).
  REQUIRED_200_HEADERS = %w[RateLimit RateLimit-Policy].freeze

  def spec = PublicApi::Spec.instance

  def api_get(path, key: nil, headers: {}, **params)
    headers = headers.dup
    headers["Authorization"] = "Bearer #{key}" if key
    get path, params:, headers:
  end

  def body = response.parsed_body

  def key_with(scopes, user: users(:member))
    issue_key(user:, scopes:).raw_key
  end

  def persons_key
    user = users(:member)
    Account.personal_for!(user).update!(terms_accepted_at: Time.current)
    issue_key(user:, scopes: %w[read:public read:persons usage:read]).raw_key
  end

  # Validates the last response against `operation_id` in the contract.
  # `projected: true` checks a `fields=` response field by field, since a
  # projection leaves out properties the item schema requires.
  # `limited: false` for a request this service did not rate-limit (the edge
  # Worker signed it, or the limiter is off), which has no RateLimit headers.
  def assert_conforms(operation_id, status: nil, projected: false, limited: true)
    op = spec.operation(operation_id)
    code = response.status.to_s
    assert_equal status.to_s, code, "expected #{status}, got #{code}: #{response.body.first(400)}" if status
    assert op.status?(code), "#{operation_id} does not declare a #{code} response (#{response.body.first(300)})"
    base = response_pointer(op, code)
    definition = spec.openapi.ref(base).value
    check_headers(definition, base, code, limited:)
    return if code == "304"

    media = response.media_type
    content = definition.fetch("content")
    assert content.key?(media), "#{operation_id} #{code} is #{media}, the contract says #{content.keys.join(', ')}"
    schema = "#{base}/content/#{escape(media)}/schema"
    if projected
      check_projected(op, schema)
    else
      errors = spec.openapi.ref(schema).validate(body).first(5).map { |e| "#{e['data_pointer']}: #{e['error']}" }
      assert_empty errors, "#{operation_id} #{code} does not match the contract"
    end
    assert_no_address_keys(body)
    body
  end

  # No response ever carries a street address key (design D9, DECISIONS 19).
  def assert_no_address_keys(value, path = "$")
    case value
    when Hash
      value.each do |k, v|
        refute_match(/address|street/i, k.to_s, "#{path}.#{k} is an address key")
        assert_no_address_keys(v, "#{path}.#{k}")
      end
    when Array then value.each_with_index { |v, i| assert_no_address_keys(v, "#{path}[#{i}]") }
    end
  end

  def assert_problem(operation_id, status, code)
    assert_conforms(operation_id, status:)
    assert_equal "application/problem+json", response.media_type
    assert_equal code, body["code"], body.inspect
    assert_equal "https://data.buildcanada.com/problems/#{code.dasherize}", body["type"]
    assert_match(/\Areq_[0-9A-HJKMNP-TV-Z]{26}\z/, body["instance"])
    body
  end

  def next_cursor = body.dig("meta", "next_cursor")

  # Rails normalizes the order of Cache-Control directives; compare them as a set.
  def assert_cache_control(expected)
    directives = ->(value) { value.to_s.split(",").map(&:strip).sort }
    assert_equal directives.(expected), directives.(response.headers["Cache-Control"]), "Cache-Control"
  end

  def with_env(values)
    saved = values.keys.to_h { |k| [ k, ENV[k] ] }
    values.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end

  def ids = body["data"].map { |d| d["id"] }

  private

  def response_pointer(op, code)
    raw = spec.document.dig("paths", op.path, op.method, "responses", code)
    raw["$ref"] || PublicApi::Spec.pointer("paths", op.path, op.method, "responses", code)
  end

  def check_headers(definition, base, code, limited:)
    declared = definition.fetch("headers", {})
    declared.each do |name, header|
      value = response.headers[name]
      if value.nil?
        flunk "#{code} is missing the #{name} header" if limited && code == "200" && REQUIRED_200_HEADERS.include?(name)
        next
      end
      pointer = header["$ref"] ? "#{header['$ref']}/schema" : "#{base}/headers/#{escape(name)}/schema"
      schema = spec.openapi.ref(pointer).value
      typed = schema["type"] == "integer" ? Integer(value, 10) : value
      errors = spec.openapi.ref(pointer).validate(typed).map { |e| e["error"] }
      assert_empty errors, "header #{name}: #{value.inspect}"
    end
  end

  def check_projected(op, schema_pointer)
    envelope = resolve(spec.openapi.ref(schema_pointer).value)
    data = envelope.dig("properties", "data")
    item_ref = body["data"].is_a?(Array) ? data.dig("items", "$ref") : data["$ref"]
    assert item_ref, "no item schema for #{op.id}"
    Array.wrap(body["data"]).each do |item|
      item.each do |field, value|
        errors = spec.openapi.ref("#{item_ref}/properties/#{field}").validate(value).first(3).map { |e| e["error"] }
        assert_empty errors, "#{op.id} field #{field}"
      end
    end
    meta = spec.openapi.ref(envelope.dig("properties", "meta", "$ref")).validate(body["meta"]).first(3).map { |e| e["error"] }
    assert_empty meta, "#{op.id} meta"
  end

  def resolve(schema)
    return schema unless schema.is_a?(Hash) && schema["$ref"]&.start_with?("#/")

    resolve(schema["$ref"].delete_prefix("#/").split("/").reduce(spec.document) { |node, t| node.fetch(t.gsub("~1", "/").gsub("~0", "~")) })
  end

  def escape(token) = ERB::Util.url_encode(token.to_s.gsub("~", "~0").gsub("/", "~1"))
end
