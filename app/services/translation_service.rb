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

      fr_md = translate_markdown(en_md)
      next unless fr_md

      record.update_column(:"#{field}_md_fr", fr_md)
    end
  end

  # Chart JSON contains identifiers and observations, not translatable prose.
  # Keep it byte-for-byte intact; authors can localize labels in the FR editor.
  def translate_markdown(markdown)
    # Use the renderer's parser rather than a second fence grammar: CommonMark
    # permits longer closing fences, whitespace before info, and closure at EOF.
    charts = Commonmarker.parse(markdown, options: Markdown::Renderer::OPTIONS).walk.select do |node|
      node.type == :code_block && node.fence_info.to_s.split.first == "buildcanada-chart"
    end
    return translate_text(markdown) if charts.empty?

    lines = markdown.lines
    parts = []
    cursor = 0
    charts.each do |node|
      position = node.source_position
      first_line = position[:start_line] - 1
      after_last_line = position[:end_line]
      prose = lines[cursor...first_line].join
      translated = translate_markdown_fragment(prose)
      return nil unless translated
      parts << translated
      parts << lines[first_line...after_last_line].join
      cursor = after_last_line
    end
    prose = lines[cursor..].join
    translated = translate_markdown_fragment(prose)
    return nil unless translated
    parts << translated
    parts.join
  end

  # translate_text strips its result, so restore the source fragment's boundary
  # whitespace. Those bytes carry list indentation and blank-line/container
  # boundaries; adding separators or dropping whitespace-only fragments changes
  # the CommonMark structure around an untouched chart.
  def translate_markdown_fragment(prose)
    return prose if prose.blank?

    translated = translate_text(prose)
    return nil unless translated

    prose[/\A\s*/] + translated.strip + prose[/\s*\z/]
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
