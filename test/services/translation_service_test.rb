require "test_helper"

class TranslationServiceTest < ActiveSupport::TestCase
  setup do
    @service = TranslationService.new
  end

  test "chart definitions are never passed to the translator" do
    chart = "```buildcanada-chart\n{\"definition\":{\"title\":\"Canada\"},\"value\":54}\n```\n"
    source = "Before\n\n#{chart}\nAfter"
    translated_inputs = []
    @service.define_singleton_method(:translate_text) { |text| translated_inputs << text; text.upcase.strip }
    result = @service.send(:translate_markdown, source)
    assert translated_inputs.none? { |text| text.include?("definition") }
    assert_includes result, chart
    assert_includes result, "BEFORE"
    assert_includes result, "AFTER"
  end

  test "CommonMark chart fences preserve JSON across delimiter and container variants" do
    charts = [
      "```buildcanada-chart\n{\"metricId\":54}\n`````\n",
      "~~~~ buildcanada-chart\n{\"metricId\":54}\n~~~~~~\n",
      "   ``` buildcanada-chart extra-info\n   {\"metricId\":54}\n   ````\n",
      "> ```buildcanada-chart\n> {\"metricId\":54}\n> ````\n",
      "- ```buildcanada-chart\n  {\"metricId\":54}\n  ````\n",
      "```buildcanada-chart\r\n{\"metricId\":54}\r\n````\r\n"
    ]
    charts.each do |chart|
      inputs = []
      @service.define_singleton_method(:translate_text) { |text| inputs << text; text.upcase.strip }
      result = @service.send(:translate_markdown, "Before\n\n#{chart}\nAfter")
      assert inputs.none? { |text| text.include?("metricId") }, chart
      assert_includes result, chart
      assert_includes result, "BEFORE"
      assert_includes result, "AFTER"
    end
  end

  test "unclosed chart fences remain protected through end of document" do
    chart = "``` buildcanada-chart\n{\"metricId\":54}\n~~\n``"
    inputs = []
    @service.define_singleton_method(:translate_text) { |text| inputs << text; text.upcase.strip }
    result = @service.send(:translate_markdown, "Before\n\n#{chart}")
    assert_equal [ "Before\n\n" ], inputs
    assert_includes result, chart
  end

  test "adjacent prose stays in the same list and blockquote containers as charts" do
    sources = [
      "- Before\n  ```buildcanada-chart\n  {\"metricId\":54}\n  ```\n  After\n",
      "> Before\n> ```buildcanada-chart\n> {\"metricId\":54}\n> ```\n> After\n",
      "- > Before\n  > ```buildcanada-chart\n  > {\"metricId\":54}\n  > ```\n  > After\n",
      "1. Before\n   ```buildcanada-chart\n   {\"metricId\":54}\n   ```\n   After\n"
    ]
    sources.each do |source|
      @service.define_singleton_method(:translate_text) { |text| text.gsub("Before", "Avant").gsub("After", "Après").strip }
      result = @service.send(:translate_markdown, source)
      assert_equal source.gsub("Before", "Avant").gsub("After", "Après"), result
      assert_equal markdown_structure(source), markdown_structure(result)
    end
  end

  test "blank lines tabs and CRLF boundaries around multiple charts remain unchanged" do
    chart = "```buildcanada-chart\r\n{\"metricId\":54}\r\n```\r\n"
    source = " \t\r\nBefore\r\n\r\n#{chart}\r\n \t\r\n#{chart}\r\nAfter\r\n\r\n"
    inputs = []
    @service.define_singleton_method(:translate_text) do |text|
      inputs << text
      text.gsub("Before", "Avant").gsub("After", "Après").strip
    end
    assert_equal source.gsub("Before", "Avant").gsub("After", "Après"), @service.send(:translate_markdown, source)
    assert_equal 2, inputs.length
  end

  test "chart-only documents do not call the translator" do
    source = " \n```buildcanada-chart\n{}\n```\n\n"
    @service.define_singleton_method(:translate_text) { |_| flunk "Chart data must not be translated" }
    assert_equal source, @service.send(:translate_markdown, source)
  end

  test "failed prose translation does not produce a partial document" do
    @service.define_singleton_method(:translate_text) { |_| nil }
    assert_nil @service.send(:translate_markdown, "Before\n\n```buildcanada-chart\n{}\n```\nAfter")
  end

  test "translates EN to FR via RubyLLM" do
    fake_response = Struct.new(:content).new("Bonjour le monde")
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_| fake_response }

    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    memo = memos(:published_memo)
    memo.update_column(:title_en, "Hello world")
    memo.update_column(:title_fr, nil)

    @service.translate_record(memo)

    memo.reload
    assert_equal "Bonjour le monde", memo.title_fr
  ensure
    RubyLLM.singleton_class.remove_method(:chat) if RubyLLM.respond_to?(:chat)
  end

  test "skips translation when FR already exists" do
    call_count = 0
    fake_response = Struct.new(:content).new("translated")
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_| call_count += 1; fake_response }

    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    memo = memos(:published_memo)
    # Both EN and FR exist in fixtures
    @service.translate_record(memo)

    assert_equal 0, call_count
  ensure
    RubyLLM.singleton_class.remove_method(:chat) if RubyLLM.respond_to?(:chat)
  end

  test "handles API errors gracefully" do
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_| raise StandardError, "API timeout" }

    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    memo = memos(:published_memo)
    memo.update_column(:title_en, "Hello world")
    memo.update_column(:title_fr, nil)

    assert_nothing_raised do
      @service.translate_record(memo)
    end

    memo.reload
    assert_nil memo.title_fr
  ensure
    RubyLLM.singleton_class.remove_method(:chat) if RubyLLM.respond_to?(:chat)
  end

  test "translate_hash_fields translates array elements" do
    fake_response = Struct.new(:content).new("Message traduit")
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_| fake_response }
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    memo = memos(:published_memo)
    memo.update_columns(
      key_messages_en: [ "Build housing", "Support innovation" ],
      key_messages_fr: []
    )

    @service.send(:translate_hash_fields, memo)

    memo.reload
    assert_equal [ "Message traduit", "Message traduit" ], memo.key_messages_fr
  ensure
    RubyLLM.singleton_class.remove_method(:chat) if RubyLLM.respond_to?(:chat)
  end

  test "translate_hash_fields skips when FR already populated" do
    call_count = 0
    fake_response = Struct.new(:content).new("translated")
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_| call_count += 1; fake_response }
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    memo = memos(:published_memo)
    memo.update_columns(
      key_messages_en: [ "Build housing" ],
      key_messages_fr: [ "Construire des logements" ]
    )

    @service.send(:translate_hash_fields, memo)

    assert_equal 0, call_count
  ensure
    RubyLLM.singleton_class.remove_method(:chat) if RubyLLM.respond_to?(:chat)
  end

  test "translate_hash_fields handles empty array" do
    memo = memos(:published_memo)
    memo.update_columns(key_messages_en: [], key_messages_fr: [])

    assert_nothing_raised do
      @service.send(:translate_hash_fields, memo)
    end
  end
  private

  def markdown_structure(markdown)
    Commonmarker.parse(markdown, options: Markdown::Renderer::OPTIONS).walk.map do |node|
      ancestors = []
      parent = node.parent
      while parent
        ancestors << parent.type
        parent = parent.parent
      end
      [ node.type, ancestors ]
    end
  end
end
