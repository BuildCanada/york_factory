class TranslationService
  MODEL = "claude-haiku-4-5-20251001"

  def translate_record(record)
    translate_plain_fields(record)
    translate_rich_text_fields(record)
    translate_key_messages(record) if record.respond_to?(:key_messages_en)
  end

  private

  def translate_plain_fields(record)
    record.class.translatable_fields.each do |field|
      next if field == :key_messages # handled separately

      en_text = record.public_send(:"#{field}_en")
      next if en_text.blank?
      next if record.public_send(:"#{field}_fr").present?

      fr_text = translate_text(en_text)
      next unless fr_text

      record.update_column(:"#{field}_fr", fr_text)
    end
  end

  def translate_rich_text_fields(record)
    record.class.rich_text_fields.each do |field|
      en_rt = record.public_send(:"#{field}_en")
      next if en_rt.blank?
      next if record.public_send(:"#{field}_fr").present?

      fr_html = translate_text(en_rt.to_s)
      next unless fr_html

      record.public_send(:"#{field}_fr=", fr_html)
      record.save!
    end
  end

  def translate_key_messages(record)
    en_messages = record.key_messages_en
    return if en_messages.blank?
    return if record.key_messages_fr.present?

    fr_messages = en_messages.map do |msg|
      fr_text = translate_text(msg)
      fr_text || msg
    end

    record.update_column(:key_messages_fr, fr_messages)
  end

  def translate_text(text)
    chat = RubyLLM.chat(model: MODEL)
    response = chat.ask(translation_prompt(text))
    response.content.strip
  rescue => e
    Rails.logger.error("Translation failed: #{e.message}")
    nil
  end

  def translation_prompt(text)
    <<~PROMPT
      Translate the following text from English to French. Preserve all HTML tags, markdown formatting, URLs, and special characters exactly as they are. Return only the translated text, nothing else.

      #{text}
    PROMPT
  end
end
