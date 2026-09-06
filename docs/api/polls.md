# Poll publications

A poll is a separate `Poll` model with its own table, bilingual editor, author,
publication/draft rules and key messages. Its canonical page is `/polls/:slug`.
Polls reuse the frontend article presentation without using memo records, routes,
engagements or slugs. No existing memo records are migrated into polls.

## Import from Surveyor

1. In Surveyor, open a campaign's Crosstabs and download **Publication draft**.
2. In York Factory, open **Polls → Import a poll from Surveyor**, choose the JSON,
   and import. The import creates a Build Canada draft, never publishes or
   overwrites an existing slug, and attaches the embedded crosstabs JSON.
3. Edit Body into the analysis report. Surveyor provides bilingual charts and
   methodology as a starting point, not a written interpretation of findings.
   Add key messages, pollster, sample size and fieldwork dates.
4. Review the crosstabs and chart data for disclosure before publication.
   Surveyor's administrative export has **unsuppressed small cells**. Replace the
   attached JSON and chart rows with the reviewed public versions as needed.
5. Upload the analysis PDF and crosstabs PDF, and optionally their French versions.
   Use the same reviewed data for PDF, JSON and inline charts.
6. Add the bilingual news release, subscriber email subject/body, and short tweet.
   Use the normal draft preview and publication controls to publish the report.
7. Copy the approved email into the existing subscriber campaign workflow
   (subscribers sync to HubSpot/Substack), and the tweet into the social workflow.
   Saving, importing or publishing does not itself send messages.

The importer accepts `kind: "buildcanada-poll-publication", schemaVersion: 1`,
with `poll` and `crosstabs` objects. Crosstabs must have `schemaVersion: 2`, a
`tables` array, and a survey slug matching the poll. Imports are limited to 25 MB.
The same service is available in Rails as `Polls::Import.call(JSON.parse(json))`.

## Authoring inline charts

Insert a fenced block with language **buildcanada-chart** anywhere in Body:

````markdown
## Support for the proposal

Analysis before the chart.

```buildcanada-chart
{
  "definition": {
    "title": "Support for the proposal",
    "data": "inline",
    "y": ["percent"],
    "types": ["discrete-bar"],
    "sourceText": "Illustrative data — not a real poll"
  },
  "dataset": {
    "manifest": {
      "name": "poll-example",
      "timeGrain": "none",
      "columns": {
        "percent": { "name": "Weighted percent", "type": "percentage", "shortUnit": "%", "decimals": 0 }
      }
    },
    "rows": [
      { "entity": "Support", "percent": 54 },
      { "entity": "Oppose", "percent": 31 },
      { "entity": "Unsure", "percent": 15 }
    ]
  }
}
```

Analysis after the chart.
````

`definition` follows `@buildcanada/charts` 1.x; `dataset` is the single-file
`{manifest, rows}` format. `definition.data` must be `"inline"`; the browser does
not fetch remote data. The CMS's rendered HTML preserves the fence, and TradingPost
replaces it with an interactive chart and optional searchable data table. Multiple
charts have independent controls and do not modify the page URL. Invalid charts
show an error in place without hiding the rest of the article. Preview each chart
before publishing. Native markdown downloads retain the exact definitions.

Use discrete bars for multi-select results: percentages can exceed 100%; do not
normalize them into relative stacks. Preserve `null` for missing values, qualified
bases, weighting notes, split-ballot wording and other interpretation constraints.
For CLI output, extract `definition` and `dataset` into separate JSON files, change
`definition.data` to the dataset filename, then use `charts validate` / `charts render`.
Automatic translation preserves chart fences byte-for-byte. Localize chart titles,
labels and notes explicitly in the French editor; never translate metric IDs/data.

## API

Authenticated `POST /api/v1/polls` and `PATCH /api/v1/polls/:slug` accept a
`poll` object with the following fields. API keys still cannot set `published_at`.

- `slug`, `title_en/fr`, `body_en/fr`, `appendix_en/fr`, `key_messages_en/fr`.
- `author_id`, `author_name`, `author_title`, `featured`, `seo_image`, `banner_image`.
- `survey_slug`, `survey_campaign_id`, `pollster`, `sample_size` (positive integer).
- `fieldwork_start`, `fieldwork_end` (ISO dates, end must not precede start).
- `methodology_en/fr`, `news_release_en/fr`, `subscriber_email_en/fr` (markdown).
- `email_subject_en/fr`, `tweet_en/fr` (text).
- Attachments: `analysis_pdf_en/fr`, `crosstabs_pdf_en/fr`, `crosstabs_json`.
  Send file uploads as multipart or use ActiveStorage signed blob IDs. PDF and JSON
  content types are validated; attachments are limited to 100 MB each.

`GET /api/v1/polls` lists polls with pagination, optional `featured` and `q` filters.
`GET /api/v1/polls/:slug` returns the article fields and a `poll` object
with survey metadata, methodology and news release (HTML and markdown), and download
URLs. English PDFs are used when a French version is missing; JSON is bilingual.

`poll.launch_copy` (email subject, email markdown, tweet) is returned **only** to
an authenticated admin preview. It is absent from public responses.

`GET /api/v1/polls/:slug/downloads/:asset` serves `analysis_markdown`,
`analysis_pdf_en/fr`, `crosstabs_pdf_en/fr`, or `crosstabs_json`. Every request checks
publication and preview access. Draft/scheduled/unpublished assets return 404 to
public callers. TradingPost proxies downloads to preserve admin preview credentials;
responses are not cached. `/polls/:slug.md` is a public, complete
markdown representation including methodology, news release and download links.

## Rollout and verification

Deploy York Factory with `bin/rails db:migrate`, then TradingPost. Surveyor's export
can roll out independently. No `bcds` release is needed: the released 1.x types
cover poll bars and comparisons.

Run the memo model/API tests, `poll_publication_test.rb`, `poll_publications_test.rb`,
`polls/import_test.rb`, and `translation_service_test.rb`. See TradingPost's
`docs/polls/README.md` for frontend checks.
