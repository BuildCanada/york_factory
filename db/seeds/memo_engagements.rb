# Sample memo with engagements (endorsements + critiques) for local development.
# Production memos come from the Webflow export (see lib/tasks/seed_cms.rake),
# which isn't available in the docker dev stack — so this creates a self-contained
# memo to exercise the engagements feature end to end.

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

# Endorsements — the model auto-approves these (Endorsement#default_to_approved).
[
  { linkedin_sub: "sample-endorser-001", name: "Jordan Avery",  given_name: "Jordan", family_name: "Avery",    email: "jordan.avery@example.com", postal_code: "K1A 0A6" },
  { linkedin_sub: "sample-endorser-002", name: "Riya Sharma",   given_name: "Riya",   family_name: "Sharma",   email: "riya.sharma@example.com",  postal_code: "M5V 2T6" },
  { linkedin_sub: "sample-endorser-003", name: "Liam Tremblay", given_name: "Liam",   family_name: "Tremblay",                                   postal_code: "H2Y 1C6" }
].each do |attrs|
  Endorsement.find_or_create_by!(memo: memo, linkedin_sub: attrs[:linkedin_sub]) do |e|
    e.assign_attributes(attrs.merge(email_verified: attrs[:email].present?))
  end
end

# Critiques — body is required; seed a mix of approved and pending for moderation.
[
  { linkedin_sub: "sample-critic-001", name: "Dana Cohen",    postal_code: "V6B 1A1", status: :approved,
    body: "Strong direction, but the timelines for municipal zoning reform feel optimistic. Phasing this over five years would de-risk delivery." },
  { linkedin_sub: "sample-critic-002", name: "Marc Belanger", postal_code: "T2P 1J9", status: :approved,
    body: "I support the supply goals, but the memo understates skilled-trades capacity. Without labour, permits won't translate into homes." },
  { linkedin_sub: "sample-critic-003", name: "Priya Nair",    postal_code: "B3J 1S9", status: :pending,
    body: "The financing section needs more detail on how CMHC instruments would be funded. As written, the fiscal impact is unclear." }
].each do |attrs|
  Critique.find_or_create_by!(memo: memo, linkedin_sub: attrs[:linkedin_sub]) do |c|
    c.assign_attributes(attrs)
    c.published_at = Time.current if attrs[:status] == :approved
  end
end

memo.reload
puts "Seeded memo '#{memo.slug}' with #{memo.endorsements.count} endorsements " \
     "and #{memo.critiques.count} critiques (#{memo.approved_critiques_count} approved)"
