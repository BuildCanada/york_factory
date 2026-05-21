module ValidatesSlugAvailability
  extend ActiveSupport::Concern

  included do
    validate :slug_not_in_history
  end

  private

  def slug_not_in_history
    return if slug.blank?
    return unless slug_changed?

    scope_value =
      if self.class.friendly_id_config.uses?(:scoped)
        serialized_scope
      end

    conflict_scope = FriendlyId::Slug
      .where(slug: slug, sluggable_type: self.class.base_class.name, scope: scope_value)

    conflict_scope = conflict_scope.where.not(sluggable_id: id) if persisted?

    if conflict_scope.exists?
      errors.add(:slug, "is already in use (current or historical) — pick another")
    end
  end
end
