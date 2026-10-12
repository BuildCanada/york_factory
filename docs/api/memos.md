# Memo authoring with user API keys

This guide has two audiences:

- A **human operator** creates and revokes the key, gives the agent its task,
  and reviews the resulting drafts.
- An **automation agent** uses the key to upload assets and create or update
  memo drafts through the API.

Production URLs:

- Admin and key management: `https://yorkfactory.buildcanada.com`
- API base: `https://yorkfactory.buildcanada.com/api/v1`

## Key types

| Prefix | Owner | Permissions | Intended use |
| --- | --- | --- | --- |
| `yfu_` | A user | The owner's current permissions | CMS agents and any other user-authenticated API route |
| `yfk_` | No user | Fixed KPI scopes such as `kpis:write` | Legacy warehouse KPI ingestion only |

Use a `yfu_` key for memo authoring. A key does not contain a copy of the
user’s role: every request checks the owner's current role. Promoting,
demoting, or deleting the user therefore changes the key's access.
Revocation takes effect immediately.

Memo writes authenticated with a `yfu_` key cannot set `published_at`. The API
ignores that field for these requests, so an agent cannot publish or schedule a
memo. Authorized interactive/Doorkeeper clients retain publishing control.

## Instructions for the human operator

### 1. Create the key

1. Sign in to York Factory as the user whose permissions the agent should use.
   The user must be an admin to write CMS records.
2. Open `https://yorkfactory.buildcanada.com/profile/api_keys`. Admins can also
   follow **Settings → My API Keys** in the sidebar.
3. Enter a specific name that identifies the workload, such as
   `Build Toronto memo import — August 2026`.
4. Select **Create API key**.
5. Copy the `yfu_...` value immediately. It is displayed only once.

Store and transfer the key like a password. Prefer a secrets manager or the
agent runtime's secret input. Do not put it in a prompt, source file, shell
history, issue, PR, or log. The database stores only a keyed digest, so York
Factory cannot recover a lost raw key; create a replacement instead.

### 2. Give the agent a bounded task

Provide:

- The source ZIP or manifest.
- The required publication enum, for example `build_toronto`.
- A clear instruction to create drafts only.
- Any editorial decisions that are not encoded in the package.
- The API base URL through configuration, not embedded in source code.

Tell the agent to stop rather than overwrite when a slug already exists unless
you explicitly want an update.

### 3. Review the result

Open **Admin → Memos** and filter Publication to **Build Toronto**. For every
memo, verify:

- Publish Status is **Draft** and Published at is blank.
- Publication is **Build Toronto**.
- Title and slug match the manifest.
- Body and appendix are complete, including raw HTML embeds.
- Every figure appears at the intended location and no
  `FIGURE_PLACEHOLDER` text remains.
- Banner and SEO images are present where supplied.
- Author and headshot are correct.
- There are three separate key-message entries, without numbering or `NOTE:`
  lines from the source file.
- Fields intentionally left blank remain blank.

For the supplied Build Toronto package, pay particular attention to the
editorial notes for memos 4, 6, and 7. Publishing remains a separate human or
authorized interactive action.

### 4. Revoke the key

Return to `/profile/api_keys` after the run and select **Revoke** unless the key
is intentionally long-lived. Confirm that the key's Last used timestamp agrees
with the import. Create a new key for a later one-off job rather than reusing an
old shared secret.

## Instructions for the automation agent

### Operating contract

The agent must:

1. Read the complete manifest and package instructions before writing.
2. Authenticate every protected request with `Authorization: Bearer yfu_...`.
3. Use the exact API publication enum, such as `build_toronto`, rather than the
   display label `Build Toronto`.
4. Check for an existing publication-and-slug pair before creating anything.
5. Upload each asset once per run and reuse its returned URL where needed.
6. Never request publication and never depend on a supplied `published_at`
   value being saved.
7. Verify each response and provide a final itemized report to the human.
8. Never print, persist, or return the raw API key.

Recommended runtime configuration:

```sh
export YORK_FACTORY_BASE_URL="https://yorkfactory.buildcanada.com"
export YORK_FACTORY_API_KEY="<provided through the runtime secret store>"
```

Examples below use those names. Do not enable shell tracing while a secret is
in the environment.

### 1. Verify authentication

```sh
curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  "$YORK_FACTORY_BASE_URL/api/v1/me"
```

Confirm that the response has `"admin": true`. Treat these responses as hard
failures:

- `401 Unauthorized`: the key is missing, invalid, or revoked.
- `403 Forbidden`: the key is valid, but its owner lacks the required role.

### 2. Check idempotency before creating a memo

An admin key can see drafts. For each manifest row, request the exact slug in
the intended publication:

```sh
curl --silent --show-error \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  "$YORK_FACTORY_BASE_URL/api/v1/memos/MEMO_SLUG?publication=build_toronto"
```

- On `404`, proceed with creation.
- On `200`, do not create a duplicate. Stop and report it, or use `PATCH` only
  when the human explicitly authorized updates.

Slug uniqueness is scoped to publication, so the publication query parameter
is required when reading or updating a non-default publication.

### 3. Resolve authors

Prefer a real team member and send `author_id`; this keeps the headshot attached
and reusable. List authors with the admin key:

```sh
curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  "$YORK_FACTORY_BASE_URL/api/v1/team"
```

Match existing authors by exact name. If a required author does not exist,
create a memo-author record with its photo:

```sh
curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  -F 'team_member[name]=Eric Richmond' \
  -F 'team_member[role]=memo_author' \
  -F 'team_member[title_en]=Country Director & CEO at Coinbase Canada' \
  -F 'team_member[profile_photo]=@authors/Eric Richmond.jpg;type=image/jpeg' \
  "$YORK_FACTORY_BASE_URL/api/v1/team"
```

Save the returned `id`. If no profile should be created, a memo may instead use
`author_name` and `author_title`; omit `author_id`. Leave every author field out
when the manifest intentionally specifies no author.

### 4. Upload and place inline figures

Upload each figure using the `file` field:

```sh
curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  -F 'file=@figures/streetcar-fig-1.png;type=image/png' \
  "$YORK_FACTORY_BASE_URL/api/v1/uploads"
```

The response contains `url` and `signed_id`. Replace the complete placeholder
line in the body markdown:

```text
[FIGURE_PLACEHOLDER: streetcar-fig-1.png — ...]
```

with markdown using the returned URL:

```markdown
![Streetcar performance chart](https://...returned-blob-url...)
```

Do not remove or rewrite Datawrapper `<iframe>` and `<script>` blocks. They are
intentional raw HTML. Saving the memo associates inline blob URLs in its
markdown with that memo so storage cleanup does not treat them as abandoned.

### 5. Parse key messages

Read the key-message file as separate numbered paragraphs. For each message:

- Remove the leading `1)`, `2)`, or `3)`.
- Preserve the message text exactly.
- Do not include a leading `NOTE:` paragraph.
- Send three repeated `memo[key_messages_en][]` multipart fields, or three
  strings in the JSON array `memo.key_messages_en`.

### 6. Create the draft

The ZIP workflow needs multipart form data because banner and SEO images are
attached directly. The body file in this example must already contain the
uploaded figure URLs:

```sh
curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  -F 'memo[slug]=torontos-streetcars-are-slow-by-choice' \
  -F "memo[title_en]=Toronto's Streetcars Are Slow by Choice" \
  -F 'memo[publication]=build_toronto' \
  -F 'memo[author_id]=AUTHOR_ID' \
  -F 'memo[body_en]=<prepared-body.md' \
  -F 'memo[appendix_en]=<content/01-streetcars-appendix.md' \
  -F 'memo[key_messages_en][]=First message' \
  -F 'memo[key_messages_en][]=Second message' \
  -F 'memo[key_messages_en][]=Third message' \
  -F 'memo[banner_image]=@banners/Streetcar Banner.png;type=image/png' \
  -F 'memo[seo_image]=@seo/Streetcars SEO.png;type=image/png' \
  "$YORK_FACTORY_BASE_URL/api/v1/memos"
```

Omit blank fields instead of sending empty file parts. Supported localized
content fields include `title_en`, `title_fr`, `body_en`, `body_fr`,
`appendix_en`, `appendix_fr`, `supporters_en`, and `supporters_fr`. Other memo
fields include `co_author_id`, `category`, `twitter_embed`, and `featured`.

A successful create returns HTTP `201`. Require all of the following before
continuing:

- Response `slug` equals the manifest slug.
- Response `publication` is `build_toronto`.
- Response `published_at` is `null`.
- Response includes URLs for every supplied banner and SEO image.

### 7. Verify the saved draft

Read it back with the same publication parameter and admin key:

```sh
curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  "$YORK_FACTORY_BASE_URL/api/v1/memos/MEMO_SLUG?publication=build_toronto"
```

Verify the full markdown, three key messages, author, attachment URLs,
publication, and `published_at: null`. Check that the body contains no
`FIGURE_PLACEHOLDER` markers. After processing all rows, list the publication
and reconcile its slugs against the manifest:

```sh
curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $YORK_FACTORY_API_KEY" \
  "$YORK_FACTORY_BASE_URL/api/v1/memos?publication=build_toronto&per_page=100"
```

The final report to the human should list each slug, creation/update status,
author, figure count, banner/SEO presence, and confirmation that it is a draft.
Report any skipped existing records or editorial warnings separately.

## API response and safety notes

- `POST /api/v1/uploads` returns `201` with a blob URL and signed ID.
- `POST /api/v1/team` returns `201` with the new author's ID.
- `POST /api/v1/memos` returns `201` for a created draft.
- `PATCH /api/v1/memos/:slug?publication=...` returns `200` for an update.
- Validation errors return `422` with an `errors` array.
- A `yfu_` key is accepted anywhere the application requires user API
  authentication; authorization still follows the key owner's role.
- Never retry a create blindly after a timeout. Check the slug first because
  the server may have committed the record before the client lost the response.
