class Warehouse::Measure::Resolver
  # Deterministic resolver for raw extracted metric names. Consults
  # warehouse.metric_aliases (kind=raw_text) before falling back to slug match.
  #
  # Returns a Measure or nil. Does not call any LLM — fuzzy resolution belongs
  # in a higher-level step that should also create review flags.

  def self.call(name, organization: nil)
    new(name, organization: organization).call
  end

  def initialize(name, organization: nil)
    @name = name.to_s.strip
    @organization = organization
  end

  def call
    return nil if @name.blank?
    by_alias || by_canonical_name || by_slug
  end

  private

  def by_alias
    scope = Warehouse::MetricAlias.raw_text.where(alias_text: @name)
    scope = scope.where(measure_id: org_measure_ids) if @organization
    scope.first&.measure
  end

  def by_canonical_name
    scope = Warehouse::Measure.where(canonical_name: @name)
    scope = scope.where(organization_id: @organization) if @organization
    scope.first
  end

  def by_slug
    slug = slugify(@name)
    scope = Warehouse::Measure.where(slug: slug)
    scope = scope.where(organization_id: @organization) if @organization
    scope.first
  end

  def org_measure_ids
    Warehouse::Measure.where(organization_id: @organization).pluck(:id)
  end

  def slugify(str)
    str.unicode_normalize(:nfkc).downcase
       .gsub(/[^a-z0-9]+/, "-")
       .gsub(/(^-+|-+$)/, "")
       .slice(0, 200)
  end
end
