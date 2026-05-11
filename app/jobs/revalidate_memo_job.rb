class RevalidateMemoJob < ApplicationJob
  queue_as :default

  def perform(slug)
    return if slug.blank?
    NextjsRevalidator.bust_memo(slug)
  end
end
