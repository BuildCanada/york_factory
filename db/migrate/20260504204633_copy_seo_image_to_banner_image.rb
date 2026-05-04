class CopySeoImageToBannerImage < ActiveRecord::Migration[8.1]
  def up
    ActiveStorage::Attachment
      .where(record_type: %w[Memo Post], name: "seo_image")
      .find_each do |seo_attachment|
        already_has_banner = ActiveStorage::Attachment.exists?(
          record_type: seo_attachment.record_type,
          record_id: seo_attachment.record_id,
          name: "banner_image"
        )
        next if already_has_banner

        ActiveStorage::Attachment.create!(
          record_type: seo_attachment.record_type,
          record_id: seo_attachment.record_id,
          name: "banner_image",
          blob_id: seo_attachment.blob_id
        )
      end
  end

  def down
    ActiveStorage::Attachment
      .where(record_type: %w[Memo Post], name: "banner_image")
      .delete_all
  end
end
