# frozen_string_literal: true

# Checks the public data API contract (docs/openapi/public/v1) without Rails or a database:
# the split source and the bundle parse, and every example in the bundle validates against
# its schema. Runs in `bin/rails test` and standalone:
#
#   bundle exec ruby -Itest test/openapi/public_v1_spec_test.rb
require "minitest/autorun"
require "json"
require "yaml"
require "json_schemer"
require "erb"

class PublicV1SpecTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SOURCE_DIR = File.join(ROOT, "docs/openapi/public/v1")
  BUNDLE = File.join(ROOT, "docs/openapi/dist/v1/openapi.json")
  METHODS = %w[get put post delete patch].freeze

  def self.doc
    @doc ||= JSON.parse(File.read(BUNDLE))
  end

  def self.openapi
    @openapi ||= JSONSchemer.openapi(doc)
  end

  def doc = self.class.doc
  def openapi = self.class.openapi

  def pointer(*tokens)
    "#/" + tokens.map { |t| ERB::Util.url_encode(t.to_s.gsub("~", "~0").gsub("/", "~1")) }.join("/")
  end

  def assert_valid(schema_pointer, value, label)
    errors = openapi.ref(schema_pointer).validate(value).first(3).map { |e| e["error"] }
    assert_empty errors, "#{label} does not validate against #{schema_pointer}"
  end

  def each_operation
    doc["paths"].each do |path, item|
      METHODS.each { |m| yield path, m, item[m] if item[m] }
    end
  end

  def test_source_files_parse
    files = Dir[File.join(SOURCE_DIR, "**/*.yaml")]
    assert_operator files.size, :>, 30
    files.each { |f| assert YAML.safe_load_file(f), "#{f} is empty" }
    root = YAML.safe_load_file(File.join(SOURCE_DIR, "openapi.yaml"))
    assert_match(/\A3\.1\./, root["openapi"])
  end

  def test_bundle_is_openapi_3_1_and_names_the_source_version
    root = YAML.safe_load_file(File.join(SOURCE_DIR, "openapi.yaml"))
    assert_match(/\A3\.1\./, doc["openapi"])
    assert_equal root["info"]["version"], doc["info"]["version"]
    assert_equal root["paths"].keys.sort, doc["paths"].keys.sort
  end

  def test_bundle_is_valid_openapi
    errors = openapi.validate.first(5).map { |e| "#{e["data_pointer"]}: #{e["error"]}" }
    assert_empty errors
  end

  def test_operation_ids_are_unique_and_every_operation_has_a_success_example
    ids = []
    each_operation do |path, method, op|
      ids << op["operationId"]
      success = op["responses"].select { |code, _| code.start_with?("2") }
      refute_empty success, "#{method.upcase} #{path} has no 2xx response"
      success.each do |code, response|
        response["content"].each do |type, media|
          refute_empty media.fetch("examples", {}), "#{method.upcase} #{path} #{code} #{type} has no examples"
        end
      end
    end
    assert_equal ids.uniq, ids
  end

  def test_every_response_example_validates
    count = 0
    each_operation do |path, method, op|
      op["responses"].each do |code, response|
        base = response["$ref"] || pointer("paths", path, method, "responses", code)
        response = openapi.ref(base).value if response["$ref"]
        (response["content"] || {}).each do |type, media|
          (media["examples"] || {}).each do |name, example|
            assert_valid("#{base}/content/#{ERB::Util.url_encode(type.gsub("/", "~1"))}/schema", example["value"], "#{method.upcase} #{path} #{code} example #{name}")
            count += 1
          end
        end
      end
    end
    assert_operator count, :>=, 25
  end

  def test_every_shared_response_example_validates
    doc["components"]["responses"].each do |name, response|
      (response["content"] || {}).each do |type, media|
        schema_ptr = pointer("components", "responses", name, "content", type, "schema")
        (media["examples"] || {}).each do |ex_name, example|
          assert_valid(schema_ptr, example["value"], "response #{name} example #{ex_name}")
        end
      end
    end
  end

  def test_every_parameter_example_validates
    params = doc["components"]["parameters"].map { |name, p| [ pointer("components", "parameters", name), p ] }
    each_operation do |path, method, op|
      op["parameters"].each_with_index do |p, i|
        params << [ pointer("paths", path, method, "parameters", i), p ] unless p["$ref"]
      end
    end
    params.each do |ptr, param|
      examples = param.key?("example") ? [ param["example"] ] : param.fetch("examples", {}).values.map { |e| e["value"] }
      refute_empty examples, "parameter #{param["name"]} has no example"
      examples.each { |value| assert_valid("#{ptr}/schema", value, "parameter #{param["name"]} example #{value.inspect}") }
    end
  end

  def test_every_header_example_validates
    doc["components"]["headers"].each do |name, header|
      assert_valid(pointer("components", "headers", name, "schema"), header["example"], "header #{name}")
    end
  end

  def test_every_schema_example_validates
    count = 0
    walk = lambda do |node, tokens|
      case node
      when Hash
        if node["examples"].is_a?(Array) && (node.key?("type") || node.key?("$ref") || node.key?("oneOf") || node.key?("allOf") || node.key?("pattern"))
          node["examples"].each_with_index do |value, i|
            assert_valid(pointer(*tokens), value, "#{pointer(*tokens)} example #{i}")
            count += 1
          end
        end
        node.each { |k, v| walk.call(v, tokens + [ k ]) unless k == "examples" }
      when Array
        node.each_with_index { |v, i| walk.call(v, tokens + [ i ]) }
      end
    end
    walk.call(doc["components"]["schemas"], [ "components", "schemas" ])
    assert_operator count, :>=, 100
  end

  def test_error_responses_are_problem_json
    each_operation do |path, method, op|
      op["responses"].each do |code, response|
        next unless code.match?(/\A(301|4|5)/)

        response = openapi.ref(response["$ref"]).value if response["$ref"]
        assert_equal [ "application/problem+json" ], response["content"].keys, "#{method.upcase} #{path} #{code}"
      end
    end
  end

  def test_units_follow_the_design_table
    expected_base = { "searchEntities" => 3, "getEntitySpendingSummary" => 3, "resolveIdentifier" => 2 }
    each_operation do |path, method, op|
      units = op.fetch("x-bc-units")
      assert_equal expected_base.fetch(op["operationId"], 1), units["base"], "#{method.upcase} #{path} base units"
      limit = op["parameters"].map { |p| p["$ref"] ? openapi.ref(p["$ref"]).value : p }.find { |p| p["name"] == "limit" }
      if limit && limit.dig("schema", "maximum").to_i > 50 && op["x-fern-pagination"]
        assert_equal 2, units["large_page"], "#{method.upcase} #{path} pages over 50 cost 2 units"
      end
    end
  end
end
