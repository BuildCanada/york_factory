require "test_helper"

class Search::Embedding::InputTest < ActiveSupport::TestCase
  test "keeps whole documents that fit the configured bound" do
    result = Search::Embedding::Input.new(max_characters: 100).prepare("Whole document")

    assert_equal "Whole document", result.text
    assert_equal "full", result.scope
    assert_equal Digest::SHA256.hexdigest("Whole document"), result.hash
    assert_equal 14, result.original_characters
  end

  test "deterministically keeps the beginning and end of oversized documents" do
    input = Search::Embedding::Input.new(max_characters: 80)
    text = ("A" * 100) + ("Z" * 100)

    first = input.prepare(text)
    second = input.prepare(text)

    assert_equal "truncated", first.scope
    assert_equal 80, first.text.length
    assert first.text.start_with?("A")
    assert first.text.end_with?("Z")
    assert_includes first.text, Search::Embedding::Input::OMISSION_MARKER.strip
    assert_equal first, second
  end
end
