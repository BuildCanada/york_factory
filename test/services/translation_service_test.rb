require "test_helper"

class TranslationServiceTest < ActiveSupport::TestCase
  setup do
    @service = TranslationService.new
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
end
