# Sample memo with engagements (endorsements + critiques) for local development.
# Production memos come from the Webflow export (see lib/tasks/seed_cms.rake),
# which isn't available in the docker dev stack — so this creates a self-contained
# memo to exercise the engagements feature end to end.
#
# Engagements now belong to real Users (created via LinkedIn/Google OAuth in
# production); here we upsert member users with a postal code so they can engage.

memo = Memo.find_or_create_by!(slug: "sample-housing-supply") do |m|
  m.title_en = "Sample Memo: Unlocking Housing Supply"
  m.category = "housing"
  m.published_at = Time.current
  m.key_messages_en = [
    "Cut municipal approval times to unlock supply",
    "Tie federal transfers to housing starts",
    "Expand skilled-trades capacity"
  ]
  m.body_en = <<~MD
    ## Summary

    This is sample memo content for local development. It outlines a plan to
    unlock housing supply across Canada through faster approvals, aligned
    incentives, and a larger construction workforce.
  MD
end

def seed_member(uid:, name:, email:, postal_code:)
  User.find_or_create_by!(provider: "linkedin", uid: uid) do |u|
    u.email = email
    u.name = name
    u.postal_code = postal_code
    u.role = :member
    u.password = Devise.friendly_token[0, 20]
  end
end

# Endorsements — the model auto-approves these (Endorsement#default_to_approved).
[
  { uid: "sample-endorser-001", name: "Jordan Avery",  email: "jordan.avery@example.com", postal_code: "K1A 0A6" },
  { uid: "sample-endorser-002", name: "Riya Sharma",   email: "riya.sharma@example.com",  postal_code: "M5V 2T6" },
  { uid: "sample-endorser-003", name: "Liam Tremblay", email: "liam.tremblay@example.com", postal_code: "H2Y 1C6" }
].each do |attrs|
  user = seed_member(**attrs)
  Endorsement.find_or_create_by!(memo: memo, user: user)
end

# Critiques — body is required; seed a mix of approved and pending for moderation.
[
  { uid: "sample-critic-001", name: "Dana Cohen",    email: "dana.cohen@example.com",    postal_code: "V6B 1A1", status: :approved,
    body: "Strong direction, but the timelines for municipal zoning reform feel optimistic. Phasing this over five years would de-risk delivery." },
  { uid: "sample-critic-002", name: "Marc Belanger", email: "marc.belanger@example.com", postal_code: "T2P 1J9", status: :approved,
    body: "I support the supply goals, but the memo understates skilled-trades capacity. Without labour, permits won't translate into homes." },
  { uid: "sample-critic-003", name: "Priya Nair",    email: "priya.nair@example.com",    postal_code: "B3J 1S9", status: :pending,
    body: "The financing section needs more detail on how CMHC instruments would be funded. As written, the fiscal impact is unclear." }
].each do |attrs|
  user = seed_member(uid: attrs[:uid], name: attrs[:name], email: attrs[:email], postal_code: attrs[:postal_code])
  Critique.find_or_create_by!(memo: memo, user: user) do |c|
    c.body = attrs[:body]
    c.status = attrs[:status]
    c.published_at = Time.current if attrs[:status] == :approved
  end
end

memo.reload
puts "Seeded memo '#{memo.slug}' with #{memo.endorsements.count} endorsements " \
     "and #{memo.critiques.count} critiques (#{memo.approved_critiques_count} approved)"
