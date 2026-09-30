# Loads the entity a /v1/entities/{id}/... request names, as of the release
# that answers: 404 when the release has no such entity, 301 to the survivor
# when it was merged (redirected). Person entities are served like any other
# class, under read:public.
module PublicApiEntityLookup
  extend ActiveSupport::Concern

  private

  def entity_query = @entity_query ||= FactFactory::EntityQuery.new(release:)

  # The entity, or nil when a response has already been rendered.
  def load_entity!
    id = PublicApi::Format.bare_id(parameters["id"], "Entity")
    entity = entity_query.find(id) or not_found!("entity #{id}")
    redirect_entity!(entity) if entity.redirected_to.present?
    entity
  end

  # 301 with a problem body (redirected): the same request on the survivor,
  # pinned to this release. The old ID keeps working.
  def redirect_entity!(entity)
    survivor = entity.redirected_to
    path = request.path.sub(%r{\A/v1/entities/[^/]+}, "/v1/entities/#{survivor}")
    location = PublicApi::Links.url(path, parameters.sent.except("as_of").merge("as_of" => release))
    raise PublicApi::Problem.new(:redirected, "Entity #{entity.entity_id} was merged into #{survivor} in release #{release}.",
      headers: { "Location" => location }, location:)
  end
end
