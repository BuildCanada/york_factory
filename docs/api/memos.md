# Memo authoring API

Any signed-in user can create a user-owned API key at `/profile/api_keys`. The raw key is
shown once. Send it on API requests as:

```http
Authorization: Bearer yfu_...
```

The key always has its owner's current permissions. Revoking the key takes
effect immediately. The same key is accepted by every user-authenticated API
endpoint, including CMS writes, uploads, saved searches,
engagements, `/api/v1/me`, and KPI admin routes. Existing KPI-scoped `yfk_`
tokens remain supported by KPI admin routes.

## Create a draft memo

`POST /api/v1/memos` accepts JSON or multipart form data. API memo writes never
accept `published_at`; a supplied value is ignored, so newly created memos are
always drafts and an API request cannot publish one.

For Build Toronto, send the enum value `build_toronto` (not the display label
“Build Toronto”):

```json
{
  "memo": {
    "slug": "torontos-streetcars-are-slow-by-choice",
    "title_en": "Toronto's Streetcars Are Slow by Choice",
    "body_en": "Markdown body",
    "appendix_en": "Markdown appendix",
    "key_messages_en": ["Message one", "Message two", "Message three"],
    "publication": "build_toronto",
    "author_name": "Eric Richmond",
    "author_title": "Country Director & CEO at Coinbase Canada"
  }
}
```

Other supported fields include `author_id`, `co_author_id`, `category`,
`twitter_embed`, `featured`, `supporters_en`, `seo_image`, and `banner_image`,
plus their French/localized counterparts. Use `GET /api/v1/team` with the API
key to see draft author records and find an existing author's ID. An override
author can use `author_name`, `author_title`, and `author_avatar`; upload the
avatar first and use the returned URL, or create a team member with a multipart
`profile_photo` and use its ID.

## Images and inline figures

Upload an inline figure as multipart form data to `POST /api/v1/uploads` using
the `file` field. The response contains `url` and `signed_id`. Put the returned
URL into the memo markdown at the figure's intended position:

```markdown
![Description](https://...returned-blob-url...)
```

Banner and SEO images can be sent directly as multipart `memo[banner_image]`
and `memo[seo_image]` fields when creating or updating the memo.

Preview drafts with `GET /api/v1/memos?publication=build_toronto` or
`GET /api/v1/memos/:slug?publication=build_toronto` using the same admin API
key. Without admin authorization these endpoints continue to return only
published records.
