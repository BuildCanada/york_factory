class TranslationService
  MODEL = "claude-haiku-4-5-20251001"

  def translate_record(record)
    translate_plain_fields(record)
    translate_markdown_fields(record)
    translate_hash_fields(record)
  end

  private

  def translate_plain_fields(record)
    record.class.translatable_fields.each do |field|
      en_text = record.public_send(:"#{field}_en")
      next if en_text.blank?
      next if record.public_send(:"#{field}_fr").present?

      fr_text = translate_text(en_text)
      next unless fr_text

      record.update_column(:"#{field}_fr", fr_text)
    end
  end

  def translate_markdown_fields(record)
    record.class.markdown_fields.each do |field|
      en_md = record.public_send(:"#{field}_en")
      next if en_md.blank?
      next if record.public_send(:"#{field}_fr").present?

      fr_md = translate_text(en_md)
      next unless fr_md

      record.update_column(:"#{field}_md_fr", fr_md)
    end
  end

  def translate_hash_fields(record)
    record.class.hash_fields.each do |field|
      en_values = record.public_send(:"#{field}_en")
      next if en_values.blank?
      next if record.public_send(:"#{field}_fr").present?

      fr_values = en_values.map do |item|
        fr_text = translate_text(item)
        fr_text || item
      end

      record.update_column(:"#{field}_fr", fr_values)
    end
  end

  def translate_text(text)
    chat = RubyLLM.chat(model: MODEL)
    response = chat.ask(translation_prompt(text))
    translated = response.content.strip
    return nil if translated.blank?
    return nil if translated.length > text.length * 3 # reject wildly long outputs
    translated
  rescue => e
    Rails.logger.error("Translation failed: #{e.message}")
    nil
  end

  def translation_prompt(text)
    <<~PROMPT
      Translate the following text from English to French. Preserve all markdown formatting (headings, lists, links, images, code blocks, inline emphasis), URLs, and special characters exactly as they are. Return only the translated text, nothing else.

      #{text}
    PROMPT
  end
end
