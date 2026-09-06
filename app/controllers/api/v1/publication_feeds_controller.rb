module Api
  module V1
    class PublicationFeedsController < ApplicationController
      def show
        return head :not_found unless PublicationFeed::KINDS.include?(params[:kind])
        response.headers["Cache-Control"] = "public, max-age=60"
        response.headers["X-Content-Type-Options"] = "nosniff"
        render body: PublicationFeed.new(params[:kind]).render, content_type: "application/rss+xml; charset=utf-8"
      end
    end
  end
end
