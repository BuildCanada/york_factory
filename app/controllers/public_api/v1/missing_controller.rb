module PublicApi
  module V1
    # Anything under /v1 that is not an operation: a 404 problem, with a
    # pointer to the index. The API is read-only, so other methods get the same.
    class MissingController < ActionController::API
      def show
        request_id = RequestId.generate
        problem = Problem.not_found("No operation at #{request.request_method} #{request.path}. Every operation is listed at /v1/openapi.json.")
        response.headers["BC-Request-Id"] = request_id
        response.headers["BC-Usage-Units"] = "0"
        render json: JSON.generate(problem.body(instance: request_id)), status: problem.status, content_type: "application/problem+json"
      end
    end
  end
end
