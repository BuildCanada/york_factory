require "test_helper"

class TranslateRecordJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "calls TranslationService with the record" do
    memo = memos(:published_memo)

    # Stub the LLM call to avoid real API calls
    fake_response = Struct.new(:content).new("Traduit")
    fake_chat = Object.new
    fake_chat.define_singleton_method(:ask) { |_| fake_response }
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    memo.update_column(:title_fr, nil)
    TranslateRecordJob.perform_now(memo)

    memo.reload
    assert_equal "Traduit", memo.title_fr
  ensure
    RubyLLM.singleton_class.remove_method(:chat) if RubyLLM.respond_to?(:chat)
  end

  test "GlobalID serialization works for enqueuing" do
    memo = memos(:published_memo)
    assert_enqueued_with(job: TranslateRecordJob) do
      TranslateRecordJob.perform_later(memo)
    end
  end
end
