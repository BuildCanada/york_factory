# Publication RSS feeds

York Factory serves RSS 2.0 at:

- /api/v1/feeds/all.xml
- /api/v1/feeds/memos.xml
- /api/v1/feeds/posts.xml
- /api/v1/feeds/polls.xml

The public base URL comes from WEBSITE_URL, defaulting to https://www.buildcanada.com.

TradingPost proxies these at /feeds/all.xml, /feeds/memos.xml, /feeds/posts.xml and
/feeds/polls.xml. RSS self links use these public frontend URLs.

Each feed contains up to 50 entries, newest publication first, with English titles,
publication dates, stable record-based GUIDs, categories, excerpts and canonical
article links. The combined limit applies across all three content types.
Toronto memos link to /toronto/memos/:slug.

Only published records appear. Future publication dates, drafts and hidden posts
are excluded regardless of credentials or preview parameters. Poll launch copy and
inline chart definitions are excluded from excerpts. Readers follow the article
link for the full content and interactive charts.

Feeds refresh with a 60-second public cache lifetime. No authentication is required.
TradingPost never forwards cookies, authorization or preview parameters to the
feed endpoints. While its poll section is admin-only, it requests all.xml?exclude=polls
and advertises only the public all/memos/posts feeds. Its polls.xml proxy requires
a live admin session. York Factory’s feed endpoints remain public.

Validation: run bin/rails test test/controllers/api/v1/publication_feeds_controller_test.rb.
Deploy York Factory before the TradingPost proxy routes.
