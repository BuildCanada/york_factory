namespace :cms do
  desc "Migrate ActionText rich-text content into markdown columns with inline image ingestion. Pass FORCE=1 to overwrite already-migrated rows."
  task migrate_rich_text_to_markdown: :environment do
    force = ENV["FORCE"] == "1"
    # Each entry: [Model, [fields]]
    targets = {
      Post     => %i[body],
      Memo     => %i[body appendix supporters],
      Builder  => %i[body author],
      Faq      => %i[answer],
      Tool     => %i[description]
    }

    rich_texts = ActionText::RichText
                   .where(record_type: targets.keys.map(&:name))
                   .order(:record_type, :record_id)

    total = rich_texts.count
    migrated = 0
    skipped = 0

    puts "[cms:migrate_rich_text_to_markdown] Processing #{total} rich-text rows..."

    rich_texts.find_each do |rt|
      model_class = rt.record_type.safe_constantize
      next unless model_class && targets.key?(model_class)

      name = rt.name.to_s # e.g. "body_en"
      match = name.match(/\A(?<field>\w+)_(?<locale>en|fr)\z/)
      unless match
        skipped += 1
        next
      end

      field  = match[:field].to_sym
      locale = match[:locale].to_sym

      unless targets[model_class].include?(field)
        skipped += 1
        next
      end

      record = model_class.find_by(id: rt.record_id)
      unless record
        skipped += 1
        next
      end

      column = :"#{field}_md_#{locale}"
      if record.read_attribute(column).present? && !force
        skipped += 1
        next
      end

      html = rt.body&.to_html.to_s
      if html.blank?
        skipped += 1
        next
      end

      markdown = Markdown::HtmlConverter.call(html, record: record)
      record.update_column(column, markdown.presence)

      migrated += 1
      print "." if (migrated % 10).zero?
    rescue => e
      warn "\n[cms:migrate_rich_text_to_markdown] Failed on #{rt.record_type}##{rt.record_id} #{rt.name}: #{e.message}"
      skipped += 1
    end

    puts "\n[cms:migrate_rich_text_to_markdown] Migrated=#{migrated} skipped=#{skipped} total=#{total}"
  end
end
