# Append-only record of key, account and admin changes
# (docs/public-interface-design.md §8.4). The table has a trigger that
# refuses UPDATE and DELETE; the model refuses them too.
class AuditEvent < ApplicationRecord
  ACTOR_KINDS = %w[user admin system].freeze

  # Who did it and from where. Built once per request (or per job) and passed
  # to the key services.
  Context = Data.define(:actor, :actor_kind, :ip, :user_agent) do
    def self.system = new(actor: nil, actor_kind: "system", ip: nil, user_agent: nil)

    def self.from_request(request, actor:, actor_kind: "user")
      new(actor:, actor_kind:, ip: request.remote_ip, user_agent: request.user_agent.to_s.first(255))
    end
  end

  belongs_to :account, optional: true
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true
  validates :actor_kind, inclusion: { in: ACTOR_KINDS }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.record!(action, context:, account: nil, subject: nil, metadata: {})
    create!(
      action:,
      account_id: account&.id,
      subject:,
      actor_user: context.actor,
      actor_kind: context.actor_kind,
      ip: context.ip,
      user_agent: context.user_agent,
      metadata:
    )
  end

  def readonly? = persisted?

  def actor_label
    return "system" if actor_kind == "system"

    [ actor_user&.email || "user ##{actor_user_id}", ("(admin)" if actor_kind == "admin") ].compact.join(" ")
  end
end
