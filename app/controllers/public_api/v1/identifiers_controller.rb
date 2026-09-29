module PublicApi
  module V1
    # GET /v1/identifiers/{namespace}/{value}: every entity holding an
    # identifier in the release (DECISIONS 28).
    class IdentifiersController < BaseController
      operation :show, :resolveIdentifier

      BUSINESS_NUMBER = /\A(\d{9})[A-Z]{2}\d{4}\z/i

      def show
        namespace = parameters["namespace"]
        value = parameters["value"].gsub(/\s/, "")
        value = value[0, 9] if namespace == "ca.cra.bn9" && value.match?(BUSINESS_NUMBER)
        query = FactFactory::EntityQuery.new(release:, persons: persons?)
        holders = query.holders(namespace, value)
        raise Problem.not_found("No entity holds #{namespace} #{value} in release #{release}.") if holders.empty?

        entities = query.refs(holders.map(&:entity_id))
        matches = holders.filter_map do |i|
          entity = entities[i.entity_id] or next
          { entity: EntitySerializer.ref(entity), identifier: EntitySerializer.identifier(i, context) }
        end
        render_data({ data: { namespace:, value:, matches: }, meta: meta, links: { self: self_link } })
      end
    end
  end
end
