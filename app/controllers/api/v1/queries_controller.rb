module Api
  module V1
    class QueriesController < ApplicationController
      def create
        question = params[:question]

        if question.blank?
          return render json: { error: "question parameter is required" }, status: :unprocessable_entity
        end

        result = NaturalLanguageQuery.new.ask(question)

        if result[:error]
          render json: { error: result[:error], sql: result[:sql] }, status: :unprocessable_entity
        else
          render json: result
        end
      end
    end
  end
end
