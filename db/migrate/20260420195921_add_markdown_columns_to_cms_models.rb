class AddMarkdownColumnsToCmsModels < ActiveRecord::Migration[8.1]
  FIELDS = {
    posts:    %i[body],
    memos:    %i[body appendix supporters],
    builders: %i[body author],
    faqs:     %i[answer],
    tools:    %i[description]
  }.freeze

  def change
    FIELDS.each do |table, fields|
      fields.each do |field|
        I18n.available_locales.each do |locale|
          add_column table, :"#{field}_md_#{locale}", :text
        end
      end
    end
  end
end
