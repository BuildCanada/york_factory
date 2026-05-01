module ApplicationHelper
  def preview_url(slug)
    return nil unless current_user&.admin?
    return nil if ENV["NEXTJS_URL"].blank?

    token = Warden::JWTAuth::UserEncoder.new.call(current_user, :user, nil).first
    query = URI.encode_www_form(token: token, slug: slug)
    "#{ENV['NEXTJS_URL']}/api/draft?#{query}"
  end
end
