module LinkedinVerified
  extend ActiveSupport::Concern

  POSTAL_CODE_REGEX = /\A[ABCEGHJKLMNPRSTVXY]\d[A-Z][ \-]?\d[A-Z]\d\z/i

  included do
    validates :linkedin_sub, :name, :postal_code, presence: true
    # Scope by :type (STI) so the same person can both endorse and critique a memo.
    validates :linkedin_sub, uniqueness: { scope: [ :memo_id, :type ] }
    validates :postal_code, format: { with: POSTAL_CODE_REGEX, message: "must be a valid Canadian postal code" }
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

    before_validation :normalize_postal_code
  end

  def display_postal_code
    postal_code
  end

  private

  def normalize_postal_code
    return if postal_code.blank?

    cleaned = postal_code.upcase.gsub(/[\s\-]/, "")
    self.postal_code = "#{cleaned[0..2]} #{cleaned[3..5]}" if cleaned.length == 6
  end
end
