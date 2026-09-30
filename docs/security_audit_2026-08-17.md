# Security Audit — York Factory

**Date**: 2026-08-17
**Scope**: Full repository (`main` @ `a8c9a2c`), static review only. No code modified, no dynamic testing, no dependency CVE scan.
**Method**: Attack-surface map first (entry points → trust boundaries → authn/authz → secrets), then data-flow tracing from each untrusted entry point to its sinks.

---

## Summary

| # | Vulnerability | Severity | Confidence |
|---|---|---|---|
| 1 | Unauthenticated HubSpot webhook — no signature verification | **High** | HIGH |
| 2 | Arbitrary R2 object read via caller-controlled `filepath` | Medium | HIGH |
| 3 | Unverified email change enables OAuth identity-merge account pre-hijacking | Medium | MEDIUM |
| 4 | Login brute-force throttle targets a route that does not exist | Low | HIGH |

**Checked and found sound** (documented in the [Negative findings](#negative-findings) section so future audits don't re-tread): SQL injection, tenancy/IDOR on member resources, the search filter DSL, draft/preview gating, token storage and randomness, secret hygiene, output escaping in admin views, deserialization.

---

## 1. HubSpot webhook accepts unauthenticated, unverified events

- **Severity**: **High**
- **Category**: `broken_access_control` / `missing_signature_verification`
- **Confidence**: **HIGH**
- **Location**: `app/controllers/webhooks/hubspot_controller.rb:1-16`, deletion sink at `:47-59`, job sink at `app/jobs/hubspot_contact_sync_from_webhook_job.rb:34-36`

### Vulnerable code

```ruby
class Webhooks::HubspotController < ApplicationController
  def create
    events = JSON.parse(request.body.read)
    events.each do |event|
      case event["subscriptionType"]
      when "contact.propertyChange" then handle_contact_property_change(event)
      when "contact.creation"       then handle_contact_creation(event)
      when "contact.deletion"       then handle_contact_deletion(event)
```

```ruby
  def handle_contact_deletion(event)
    contact_id = event["objectId"]
    contact = HubspotContact.find_by(hubspot_contact_id: contact_id)
    if contact
      Rails.logger.info "Deleting contact: #{contact.email}"
      contact.destroy!
```

`ApplicationController` includes only `Authenticatable`, which defines `authenticate_api_user!` / `authenticate_admin!` as *private helpers* — it installs no `before_action`. This controller declares none either. `POST /webhooks/hubspot` is confirmed routable and reachable with no credential. HubSpot signs every webhook (`X-HubSpot-Signature-v3`, HMAC-SHA256 over method + URI + body + timestamp); nothing in `app/`, `config/`, or `lib/` reads or verifies that header — a repo-wide search for `signature` / `X-HubSpot` returns only an unrelated `MessageVerifier` rescue in `has_localized_markdown.rb:82`.

### Attack scenario

Anyone who learns the endpoint (it is guessable, and appears in HubSpot-side configuration) can:

1. **Destroy CRM mirror records.** `POST /webhooks/hubspot` with
   ```json
   [{"subscriptionType":"contact.deletion","objectId":12345}]
   ```
   deletes the local `HubspotContact` row for that ID — no auth, no signature, no rate limit on this path. Iterating `objectId` over a plausible ID range wipes the local contact mirror, which holds member PII (email, name, and the other synced HubSpot properties). Recovery depends on a re-sync from HubSpot succeeding; deletion itself is silent apart from a log line.
2. **Drive attacker-chosen server-side API calls.** `contact.creation` / `contact.propertyChange` enqueue `HubspotContactSyncFromWebhookJob.perform_later(contact_id, event)` with a fully attacker-supplied `contact_id`. The job authenticates to HubSpot with the app's own access token (`Rails.application.credentials.dig(:hubspot, :access_token)`) and pulls that contact into the local DB. This lets an unauthenticated outsider force the app to fetch and materialize arbitrary contacts from the CRM by ID.
3. **Delete via the fetch path too.** When the forced fetch 404s, the job's rescue deletes the local row (`hubspot_contact_sync_from_webhook_job.rb:34-36`) — a second, indirect route to the same destruction.

No user interaction and no prior access is required. The only precondition is knowing the URL.

### Fix

Verify the HubSpot v3 signature before dispatching any event, and reject on mismatch:

```ruby
class Webhooks::HubspotController < ApplicationController
  before_action :verify_hubspot_signature!

  private

  def verify_hubspot_signature!
    secret    = Rails.application.credentials.dig(:hubspot, :client_secret)
    timestamp = request.headers["X-HubSpot-Request-Timestamp"]
    signature = request.headers["X-HubSpot-Signature-v3"]

    return head :unauthorized if secret.blank? || signature.blank? || timestamp.blank?
    # Reject replays outside HubSpot's 5-minute window.
    return head :unauthorized if Time.at(timestamp.to_i / 1000) < 5.minutes.ago

    base     = "#{request.method}#{request.original_url}#{request.raw_post}#{timestamp}"
    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, base))

    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
end
```

Note `request.raw_post` rather than `request.body.read` so the body is still readable after verification. Secondary hardening: treat `objectId` as untrusted (validate it is an integer) and consider making deletion a soft-delete so a spurious event is recoverable.

### What would confirm or rule this out

Confirmed by `curl -X POST https://<host>/webhooks/hubspot -d '[{"subscriptionType":"contact.deletion","objectId":<known_id>}]' -H 'Content-Type: application/json'` against a staging instance and observing the row disappear. The only thing that would downgrade it is an undocumented network control in front of the app (WAF rule or IP allowlist restricting `/webhooks/*` to HubSpot's ranges) — I cannot see deployed edge config from the repo. That would be defence-in-depth, not a substitute: the signature check belongs in the app.

---

## 2. Arbitrary R2 object read via caller-controlled `filepath`

- **Severity**: Medium
- **Category**: `broken_access_control` / `path_traversal` (object-store key injection)
- **Confidence**: **HIGH**
- **Location**: `app/controllers/api/v1/kpis/admin/documents_controller.rb:24` and `:86` (write), `:63-73` (read), `app/services/r2_storage.rb:18-20`

### Vulnerable code

```ruby
def document_params
  params.require(:document).permit(
    ..., :filepath, :content_hash, :agent_run_id
  ).to_h.symbolize_keys
end
```
```ruby
doc.assign_attributes(..., filepath: attrs[:filepath], ...)
```
```ruby
def archive_download
  doc = ::Warehouse::KpiDocument.find(params[:id])
  return render json: { error: "not_archived" }, status: :not_found if doc.filepath.blank?

  body = R2Storage.new.download(key: doc.filepath)
  send_data body, type: doc.filepath.end_with?(".pdf") ? "application/pdf" : "text/html", disposition: "inline"
```

`filepath` is a permitted, caller-writable attribute. `archive_download` passes it straight to `R2Storage#download`, which calls `get_object` with no key prefix constraint. The write path (`archive`) *does* compute a safe key (`kpi_documents/:id/:hash.:ext` at `:77-80`), but nothing forces `filepath` to have come from that path.

### Attack scenario

A holder of a `kpis:write` `Warehouse::ApiToken` — a machine credential issued to the KPI extraction agent, deliberately *less* privileged than an admin user (`api/v1/kpis/admin/base_controller.rb:37-49`) — does:

```http
POST /api/v1/kpis/admin/documents
Authorization: Bearer yfk_...
{"document": {"jurisdiction_slug":"canada","fiscal_year":"2024-25",
              "doc_url":"https://example.com/x.html",
              "filepath":"raw/estimates/2024/some_ingestion.csv"}}
```

then `GET /api/v1/kpis/admin/documents/<id>/archive`, and receives those bytes. Because `R2_BUCKET` is the shared **archival** bucket (raw ingestion CSVs, shapefiles, scraped source snapshots — see `CLAUDE.md`), a scoped extraction token becomes a read primitive over every object in it. Keys are semi-predictable from the ingestion naming conventions, and a wrong guess is a cheap 404, so enumeration is practical.

Impact is bounded by the credential requirement (not anonymous) and by the bucket holding mostly public-source government data — which is why this is Medium, not High. The security property that breaks is scope isolation: `kpis:write` is supposed to grant KPI writes, not bucket-wide reads.

### Fix

Do not accept `filepath` from the client — derive it. Remove `:filepath` (and, for the same reason, `:content_hash`, which is a server-computed integrity value) from the permitted list, and let only `#archive` set it. Belt-and-braces, constrain the read:

```ruby
ARCHIVE_PREFIX = "kpi_documents/".freeze

def archive_download
  doc = ::Warehouse::KpiDocument.find(params[:id])
  return render json: { error: "not_archived" }, status: :not_found if doc.filepath.blank?
  unless doc.filepath.start_with?(ARCHIVE_PREFIX) && !doc.filepath.include?("..")
    return render json: { error: "invalid_archive_key" }, status: :unprocessable_entity
  end
  ...
```

Longer term, give the R2 credential used by this path a bucket policy scoped to the `kpi_documents/` prefix.

### What would confirm or rule this out

Confirmed by issuing a `kpis:write` token in staging and running the two requests above against a known non-KPI key. Ruled out only if the R2 access key in use is already prefix-scoped by IAM policy — I cannot inspect the bucket policy from the repo, and the single `R2Storage` client used for all archival reads and writes suggests it is not.

---

## 3. Unverified email change enables OAuth identity-merge account pre-hijacking

- **Severity**: Medium
- **Category**: `authentication` / `account_takeover`
- **Confidence**: **MEDIUM**
- **Location**: `app/controllers/profile_controller.rb:43-45`, merge logic at `app/models/user.rb:68`

### Vulnerable code

```ruby
def profile_params
  params.require(:user).permit(:name, :email,
    :postal_code, :address_line1, :address_line2, :city, :province)
end
```
```ruby
# User.from_omniauth
user = find_by(email:) if email.present? && email_verified != false
```

`User` enables `:database_authenticatable, :registerable, :recoverable, :trackable, :omniauthable, :jwt_authenticatable` — **not `:confirmable`**. A member can therefore PATCH `/profile` and change `email` to any address that is not already taken; the change is effective immediately, with no email sent to either the old or the new address. Separately, `from_omniauth` links a *new* provider identity onto an existing account whenever the provider-verified email matches an existing row.

### Attack scenario

Classic pre-hijack, no victim interaction until the final step:

1. Attacker self-registers via Google or LinkedIn (open to anyone — that is the documented design for memo engagement).
2. Attacker PATCHes `/profile` setting `email` to `victim@company.com`, an address they do not control and which has no account yet. Uniqueness passes; no verification occurs.
3. Attacker sets a known password via the password-reset flow on their *original* address, or simply retains their session.
4. Victim later signs in with Google/LinkedIn using `victim@company.com`. `from_omniauth` finds the attacker's row by email, treats it as the same person, and attaches the victim's identity to it (`user.rb:80`).
5. Attacker and victim now share one account. The attacker retains password login and can read anything the victim subsequently does there — profile data (name, postal code, street address, city, province), saved searches and their results, issued API keys, and the memo endorsements/critiques published under that identity.

**Why not High**: the `validates :email, uniqueness: true` guard means an *existing* account — including any admin — cannot be targeted, only an address that has never registered. There is also no email-based authorization anywhere in the app (verified: no `@buildcanada.com` domain check gates any role), so this yields no privilege escalation on its own. The ceiling is per-user account confusion, and the ideal target is a member who has not yet signed up.

### Fix

Two independent changes, either of which breaks the chain; do both:

1. **Do not let the profile form change email unverified.** Either drop `:email` from `profile_params` and handle email changes through a dedicated confirmation flow, or enable Devise `:confirmable` with `reconfirmable = true` so the new address only becomes the account's email after the user clicks a link sent to it.
2. **Only merge on a provider-verified email that the account itself has verified.** In `from_omniauth`, gate step 2 on the local record also being confirmed, so an unverified self-asserted address can never absorb an incoming identity:
   ```ruby
   user = find_by(email:) if email.present? && email_verified != false
   user = nil unless user&.confirmed?   # requires :confirmable
   ```

### What would confirm or rule this out

Confirmed end-to-end in staging: register account A via Google, PATCH its email to an unregistered address B, then complete a Google sign-in as B and assert you land in account A (same `users.id`, attacker's password still valid). Ruled out if there is an unmodelled constraint I did not find — e.g. a DB trigger or a frontend that never exposes the email field. Note the frontend not exposing it is *not* a mitigation: `PATCH /profile` is reachable directly with a session cookie and CSRF token.

---

## 4. Login brute-force throttle targets a non-existent route

- **Severity**: Low
- **Category**: `security_misconfiguration`
- **Confidence**: **HIGH**
- **Location**: `config/initializers/rack_attack.rb:10-12`

### Vulnerable code

```ruby
throttle("admin/login/ip", limit: 5, period: 60) do |req|
  req.ip if req.path == "/admin/login" && req.post?
end
```

The route table has no `/admin/login`. `devise_for :users, path: "", path_names: { sign_in: "login" }` puts the form at **`POST /login`** (confirmed against the live route set). The discriminator never matches, so the throttle is dead code and password login is unthrottled. The other two throttles in the file (`/api/v1/subscribers`, `/api/v1/auth/google`) do use correct paths.

Also unthrottled and worth covering in the same change: `POST /password` (`Users::PasswordsController#create`), which sends a reset email per request to any address, and `PUT /password`, which submits reset tokens.

### Attack scenario

Unlimited credential-stuffing and password-guessing against `POST /login` from a single IP. `Users::SessionsController#create` does a straight `valid_password?` check with no lockout — Devise `:lockable` is not enabled — so nothing else bounds attempts. The practical severity depends on password strength; note that admin-created users get `Devise.friendly_token(20)` and reset by email, so guessable passwords come only from users who chose their own.

### Fix

```ruby
throttle("login/ip", limit: 5, period: 60) do |req|
  req.ip if req.path == "/login" && req.post?
end

# Guessing one password across many accounts evades a per-IP limit.
throttle("login/email", limit: 5, period: 20.minutes) do |req|
  req.params.dig("user", "email").to_s.downcase.presence if req.path == "/login" && req.post?
end

throttle("password_reset/ip", limit: 5, period: 1.hour) do |req|
  req.ip if req.path == "/password" && req.post?
end
```

Add a regression test asserting the 6th `POST /login` returns 429 — that is what keeps a future route rename from silently killing the throttle again. Consider enabling Devise `:lockable` as a second layer.

### What would confirm or rule this out

Confirmed by reading the route table (done) — the string literal simply does not match any path. `curl` looping `POST /login` 20 times in staging and never seeing a 429 confirms it dynamically. Ruled out only if an edge/CDN rate limit already covers `/login`, which I cannot see from the repo.

---

## Negative findings

Traced and found sound. Recorded so the next audit can start here rather than repeat the work.

- **SQL injection** — no injectable sink found. Every raw fragment either uses bind parameters (`where("confidence < ?", ...)`) or wraps user input in `sanitize_sql_like` before interpolating into `ILIKE` (`admin/users_controller.rb:9-11`, `admin/subscribers_controller.rb:5`, `warehouse/address.rb:9-10`, `warehouse/geo_boundary.rb:22`, `memo.rb:36-37`). `population_loader.rb:25` builds its bulk update via `sanitize_sql_array`. The only `Arel.sql` is a static string (`warehouse/human_review_queue_entry.rb:12`). No parameter-driven `order` anywhere.
  - Two `ILIKE` sites interpolate without `sanitize_sql_like`: `admin/kpis/measures_controller.rb:15` and `api/v1/kpis/documents_controller.rb:32`. Both still bind via `?`, so this is a LIKE-metacharacter issue (`%`/`_` widening a search), not injection. Not a vulnerability; worth tidying for consistency.
- **Tenancy / IDOR on member resources** — consistently scoped through the owner association: `current_user.saved_searches.find(params[:id])` (`saved_searches_controller.rb:95`, `saved_search_runs_controller.rb:7`, `saved_search_matches_controller.rb:7`), `current_user.api_keys.active.find(params[:id])` (`api_keys_controller.rb:17`). A cross-user ID yields `RecordNotFound`, not another user's data.
- **Search filter DSL** — `POST /api/v1/spending/search` is unauthenticated and takes a caller-authored filter tree, but scope predicates are force-ANDed at the top level (`spending/searches_controller.rb:43-45`), as is `visibility Eq public` in `Search::QueryCompiler#filters` (`:33-42`). A caller cannot widen scope; operators come from a fixed map (`:3-11`) and fields are validated against the realm contract.
- **Draft / preview gating** — `preview_mode?` (`cms_base_controller.rb:15-29`) resolves the *token owner* and checks `admin?`, never a client-supplied flag; the comment at `:26-27` shows this was deliberate. Unpublished memos, posts, builders, and elections are correctly invisible without an admin credential.
- **Vertical privilege escalation in admin** — an admin cannot assign `superadmin` (`admin/users_controller.rb:69-72`), cannot delete users (`require_superadmin!`), and cannot edit their own row (`prevent_self_management!`). `/admin/jobs` (MissionControl) is gated by a routing constraint reading `warden` directly (`routes.rb`).
- **Missing authz on CMS writes** — checked every `resources` block with full CRUD under `/api/v1`. All write actions carry `before_action :authenticate_admin!`. `Api::V1::TestimonialsController` omits `:update` from its filter list (`:4`) but defines no `update` action, so the route raises rather than writing — no exposure. Worth removing the dead route.
- **Token handling** — `ApiKey` and `Warehouse::ApiToken` store only HMAC-SHA256 digests peppered with `secret_key_base`, generate raw tokens with `SecureRandom.urlsafe_base64(32)`, and check a `revoked_at IS NULL` scope on every authentication. `ApiKey.authenticate` deliberately copies no role, so a demotion takes effect immediately (`authenticatable.rb:6-9`).
- **Secret hygiene** — `.env` and `config/master.key` are gitignored (`.gitignore:11`, `:33`) and `git ls-files` confirms neither is tracked; only `credentials.yml.enc` and a `.sample` are committed. OAuth access/refresh tokens go to encrypted `Identity` columns and are stripped from the stored `raw` payload (`user.rb:111`, `:126`).
- **XSS in admin views** — swept `app/views/**` for unescaped output. One `html_safe`, on a static inline-style literal (`admin/users/index.html.erb:18`). User-submitted critique bodies render escaped (`admin/critiques/show.html.erb:36`). `AdminMarkdownHelper#render_markdown` sanitizes against an explicit tag/attribute allowlist.
- **`Markdown::Renderer` with `unsafe: true`** (`app/services/markdown/renderer.rb:10-11`) — raw HTML and `tagfilter: false` are intentional so embeds survive, and the input is admin-authored. Not reported as a vulnerability: it is an accepted trust decision, documented in the file. It does mean **an admin can inject script into the consuming frontend**, so it is only as safe as the assumption that admin accounts are trustworthy and uncompromised. Worth revisiting if the CMS ever accepts non-admin markdown.
- **SSRF** — `Markdown::ImageIngestor#fetch` (`:69-85`) does server-side GETs with up to 5 redirect hops and no host/IP filtering, and `archive` fetches are similar. Reachable only from admin-authored content, so not reported. If any non-admin path ever feeds it, this becomes a real finding: add an allowlist and block link-local/private ranges, re-checking after every redirect.
- **Open redirect** — `safe_return_to` (`omniauth_callbacks_controller.rb:65-67`) rejects absolute and protocol-relative targets, and the redirect passes `allow_other_host: false`.
- **CSRF** — `load_defaults 8.1` enables forgery protection for the `ActionController::Base` descendants (admin, profile, sessions). Bearer-only API controllers descend from `ActionController::API`; the `/api/v1/*` CORS rule sends no credentials, so `CORS_ORIGINS` defaulting to `*` does not expose them.
- **Unsafe deserialization** — none. No `YAML.load`, `Marshal.load`, `Oj.load`, or `from_yaml` anywhere in `app/`, `lib/`, or `config/`.
- **Information disclosure** — password reset returns a uniform "If that email exists" response (`users/passwords_controller.rb:22`). `/api/v1/me` deliberately omits the internal user ID. Pledge share pages are keyed on an unguessable token and never return the pledger's email (`election_pledges_controller.rb:33-44`). PostHog receives `posthog_distinct_id` (the primary key), not PII, as the distinct ID — though `posthog_properties` (`user.rb:151-161`) does send email, name, and postal code to PostHog as person properties, which is a data-processing decision to be aware of rather than a code defect.

---

## Coverage and limits

**Not examinable from the repository**
- Deployed configuration: the real `CORS_ORIGINS`, whether `DEVISE_JWT_SECRET_KEY` is set or silently falling back to `secret_key_base` (`authenticatable.rb:67`), Kamal secrets, R2 bucket policies, and any WAF/CDN in front of the app. Findings 1, 2, and 4 each note where an edge control could reduce (but not remove) real-world exploitability.
- Doorkeeper application rows — which clients are `trusted?` (they skip the authorization prompt, `doorkeeper.rb`), their registered `redirect_uri`s, and confidential-vs-public status. This determines whether the absence of explicit PKCE enforcement matters; **unresolved, and worth checking in the database.**
- External services: HubSpot, Turbopuffer, Azure Cohere, Webflow, Luma, Zernio, PostHog. Client code reviewed; their side and the true scope of the credentials held are not visible.

**Not read in full**
- The ~40 `Warehouse::` KPI/spending models and pipeline loaders (reviewed for SQL sinks only, not end-to-end logic).
- All job classes and the 17 `lib/tasks/*.rake` files, beyond the HubSpot webhook job traced for finding 1.
- `app/views/**` beyond the unescaped-output sweep described above.
- The `test/` tree.

**Not run**
- Dependency CVE scan. Direct deps are current (`rails 8.1`, `devise 5.0.4`, `doorkeeper 5.9.3`, `nokogiri 1.19.4`, `jwt 3.2.0`, `commonmarker 2.9.0`) and `Gemfile.lock` is committed and complete, but **"no known CVEs" is unverified** — no advisory database was available. Run `bundler-audit check --update` to close this gap.
- Brakeman, and any dynamic or authenticated testing.

**Logic I could not fully settle statically**
- The field-whitelisting depth of each `Search::Realms::*#validate_definition`. I read the compiler and confirmed scope pinning; I did not read every realm contract, so a permissive field list in one realm could expose attributes I have not enumerated.
- Devise's exact CSRF strategy as applied to the hand-rolled `Users::SessionsController` — protection is enabled framework-wide, but I did not confirm the failure mode is `:exception` rather than `:null_session` for that specific controller.
