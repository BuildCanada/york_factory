# CPAC broadcast archive

The archive captures CPAC TV and simultaneous events, backfills historical programmes, extracts English/French embedded captions, remuxes playback, indexes transcripts, and exports clips from the Rails admin.

Open `/admin/broadcasts` as an admin. Click **Discover CPAC streams**, then **Start capture** for a stream. Recurring discovery runs every 15 seconds in production. New streams stay paused unless `CPAC_CAPTURE_ENABLED=true`; this setting does not overwrite an existing stream's manual pause. Upcoming events are discovered before their scheduled start. A watchdog recovers due captures after workers restart.

## Storage and data model

The implementation uses the simplicity review's five warehouse tables:

| Table | Purpose |
| --- | --- |
| `warehouse.media_streams` | Provider identity, public titles, source pages, live manifest |
| `warehouse.media_tracks` | Video, audio, and caption-service identity |
| `warehouse.media_objects` | Immutable source/manifest objects, remuxed parts, and WebVTT files |
| `warehouse.media_recordings` | Named time windows over a stream (daily for continuous channels) |
| `warehouse.media_transcript_passages` | Searchable English/French transcript windows |

`media_capture_states` and `media_clips` are primary application tables. Capture scheduling, leases, errors, clip ownership, and user labels stay outside the warehouse. Raw cues live in archived WebVTT files, not a separate cue table. Live source UTC anchors and native timestamp evidence preserve track alignment; missing live anchors fail visibly. Finite historical archives may use an explicitly labelled publication-date reference when original media timestamps are absent.

Recordings do not own media objects, so daily rotation does not copy transport segments. Clip requests store absolute timestamps, one audio choice, and explicit caption choices. A clip belongs to its creator, including when its creator is an admin.

## Running

See [Production rollout](production.md) for database prerequisites, R2 CORS, and environment configuration.

1. Install the repository's Ruby version and gems. Enable PlanetScale TIN in production or install Lead locally (below), then run `bin/rails db:migrate`. The Docker image includes FFmpeg/ffprobe. Locally, install FFmpeg separately.
2. Configure archival R2 using the existing `credentials.r2` values (`endpoint`, `access_key_id`, `secret_access_key`, `bucket`). The archive adapter also accepts `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, and `R2_BUCKET`. User clip exports use the app's configured ActiveStorage service, which should be `r2_active_storage` in production.
3. Allow the admin origin in the archival bucket's CORS configuration for signed GET/range requests. Playback uses short-lived signed URLs; the bucket can remain private. HLS.js is pinned in the import map and loaded only on recording playback pages.
4. Run the existing Solid Queue workers and recurring scheduler. All jobs use the **default queue**. No additional queue or worker topology is introduced. Measure queue latency under concurrent events before enabling continuous unattended capture; `JOB_CONCURRENCY` controls existing worker processes.
5. Use the dashboard to discover and enable streams, or set `CPAC_CAPTURE_ENABLED=true` before discovering new streams to capture all newly discovered TV/events.
6. Broadcast search runs directly in PostgreSQL using TIN. No Turbopuffer or embedding credentials are needed for broadcasts. Other datasets retain their existing search integration.

The discovery source is CPAC's public website endpoint:

```text
https://www.cpac.ca/api/1/services/item-list.json?localId=%2Fsite%2Fcomponents%2Fcpac-item-lists%2Flivestreams.xml&removeCpacTv=false
```

Identity is `(provider, episodeId)`, not the manifest URL. The adapter selects one video rendition up to 720p, separately captures the advertised English/French/floor audio tracks, and maps CPAC's embedded caption fields explicitly. Track labels and manifests can change during a programme. Source bytes are uploaded before an idempotent ledger entry is committed; per-stream leases fence stale capture writes.

## Playback, captions, and search

Processing normally closes a part after roughly 60 seconds of captured media. Source acquisition follows the HLS target duration. Caption search and archived playback therefore lag the provider by approximately a part plus processing time; these are not sub-second outputs. Finalized short tails and interrupted intervals are handled separately. Processing retries storage/network failures, failed media commands, and invalid probe/output timing up to four attempts with backoff, including after capture polling has stopped. Exhausted failures remain visible in the job dashboard.

Playback is an authenticated, bounded 32-minute HLS snapshot (two minutes of lead-in plus a full 30-minute clip) assembled from remuxed MPEG-TS parts. Language-specific derived parts repeat video bytes to keep V1 language switching simple; source video is captured once. This intentionally replaces the original proposal's more complex fragmented-MP4 packaging. The player preserves gap intervals and shows unavailable footage. Refresh a playback window to include newer parts. Corrected remux recipes rebuild from retained source segments and atomically supersede older playback parts; playback and new clip exports use the replacements while original rows and bytes remain available for provenance.

English/French captions are extracted from A53/CEA-608 fields with state replay across processing boundaries. Both languages were verified on short public CPAC parliamentary and CPAC TV samples on September 21, 2026. This is an explicit CPAC mapping, not a language assumption for future providers. Some programmes do not carry both languages. Empty decoded caption windows are recorded as empty; no machine translation or automatic speech recognition is substituted.

WebVTT files retain cue timing. Search passages remove repeated roll-up lines. A partial TIN index covers published transcript text; searches apply recording, language, and time filters in PostgreSQL. New passages, corrections, and withdrawals are visible transactionally, without embedding generation or an asynchronous search sync. Archive results use `tin.score(ctid)` ranking; recording results stay chronological for clipping. Broadcasts are not offered in the generic Turbopuffer search or saved-search interface.

Queries use [TinQL](https://planetscale.com/docs/postgres/search): words combine with AND, quoted text matches a phrase, and uppercase `OR` supports alternatives. The default Unicode tokenizer ignores case and accents, including French accents. This is lexical search; it does not generate semantic embeddings. Search results and expanded subtitle cues highlight TIN-matched spans, including accent-folded terms and phrases. Opening an archive result preserves its query and language in the clipping workspace. Highlighted text is escaped as text before rendering; source captions cannot inject HTML.

## Local development

Set `BROADCAST_STORAGE_SERVICE=local_archive` to store captured media under `storage/broadcast_archive` without R2. This option is limited to development/test and serves signed local URLs through Rails. Clip attachments use the existing local ActiveStorage service. Set `PORT` to keep generated download URLs aligned with the server port.

Use an isolated database suffix (`CONDUCTOR_WORKSPACE_NAME`) and run the web server and `bin/jobs` with the same database and storage environment. Local launch scripts, credentials, and captured media are not part of this repository.

## Local search extension

[Lead](https://github.com/planetscale/lead) implements TIN's SQL interface for development and testing on PostgreSQL 17/18. It is not a production search engine and its performance does not represent TIN. We pin Lead to `bd95c7e51b6afce81396790852ee2f2c169570ad`, Rust 1.96.0, and cargo-pgrx 0.19.1.

The development/test image bundles PostgreSQL 18, PostGIS, and Lead:

```sh
docker build -t york-postgres-lead docker/postgres-lead
docker run --name york-postgres-lead -e POSTGRES_PASSWORD=postgres -p 55432:5432 -d york-postgres-lead
PGHOST=127.0.0.1 PGPORT=55432 PGUSER=postgres PGPASSWORD=postgres bin/rails db:create db:migrate
```

For an existing PostgreSQL installation, build Lead against that server's `pg_config` (not another PostgreSQL installation on `PATH`):

```sh
rustup toolchain install 1.96.0 --profile minimal
cargo +1.96.0 install cargo-pgrx --version 0.19.1 --locked
git clone https://github.com/planetscale/lead.git /tmp/york-lead
cd /tmp/york-lead
git checkout bd95c7e51b6afce81396790852ee2f2c169570ad
# Set this to the installed server's pg_config; use pg18 for PostgreSQL 18.
export LEAD_PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config
export PGRX_HOME=/tmp/york-lead-pgrx
cargo +1.96.0 pgrx init --pg17="$LEAD_PG_CONFIG"
cargo +1.96.0 pgrx install --package tin --no-default-features --features pg17 --pg-config "$LEAD_PG_CONFIG" --release
```

Installation requires write access to that server's extension directories. On macOS, use the Docker image or a writable Homebrew PostgreSQL installation; macOS may block writes inside the Postgres.app bundle. The Rails migration creates the `tin` extension and builds the published-transcript index concurrently. No server restart or `shared_preload_libraries` change is needed. Install the extension files before migrating or loading `db/structure.sql`, including test databases. CI installs the same pinned Lead build into its PostgreSQL service.

## Historical backfills

Open **Historical backfills** from `/admin/broadcasts`. Choose an inclusive date range (up to 366 days) and either **Find listings only** or **Find and queue all captures**. Listing-only requests let you review programmes and queue individual captures afterward. Each request has a progress page with per-broadcast states and errors; failed work can be retried.

Discovery reads CPAC's public, paginated `/search?startDate=YYYY-MM-DD&endDate=YYYY-MM-DD&page=N&order=desc` listings and resolves episode pages to archive manifests. A date range selects the provider's programme listing date; it does not trim the downloaded programme to those dates. Backfills archive complete available episodes from their beginning in bounded, resumable batches, then use the same remux, caption, and search pipeline as live capture. Missing or unsupported source media is shown as an error rather than treated as a successful recording. For finite archives without program-date-time, the provider publication date anchors elapsed offsets; metadata and the recording page explicitly distinguish this from original airtime. Live capture still requires provider media timestamps.

`broadcast_backfill_requests` and `broadcast_backfill_items` are primary application tables. They contain the requesting user, progress, retries, and capture leases. Historical programme metadata and downloaded media remain in the warehouse. Archive streams use `episodeId:archive`, with the original CPAC ID in `metadata.canonical_external_id`, so live and historical timelines cannot collide. Jobs run on the existing default queue. Discovery yields after five pages and dispatch yields after 100 broadcasts. A minute watchdog recovers stale work; media retries use durable backoff and stop after six consecutive transient failures. Empty or unfinished archives fail visibly and can be retried after the provider makes them available.

## Clips

Search timestamped subtitles on the recording page in either or both languages. Search covers the entire recording, with paginated results; without a query, the transcript follows the current 30-minute playback window. Each matching segment offers **Set clip in**, **Set clip out**, and **Clip this segment**. Expand **Show exact subtitle times** to select boundaries from individual WebVTT cues. Clip selections persist when searching, paging results, or loading a different playback window.

The recording editor includes a draggable IN/OUT timeline, selection zoom, typed timecodes, playback speed, 0.1-second fine seeking, and selection preview with optional looping. Space toggles playback, I/O set boundaries, and arrow keys seek (Shift for fine seeking). Clip drafts retain the title, boundaries, export mode, and subtitle choices in the browser tab. Missing footage and selections longer than 30 minutes block export.

Select an audio language, choose English/French subtitle files, and export. Precise cuts re-encode H.264/AAC at video-frame precision by default. Fast copy remains available; keyframe alignment can expand its interval. The clip page shows export progress, requested and actual boundaries, video playback, and downloads. Subtitle sidecars are intersected with the exported range and rebased to zero. For each language, export selects a caption track with complete coverage of the actual exported interval, including any keyframe expansion; obsolete or gapped tracks are skipped.

Missing source/playback coverage or requested subtitle coverage fails with a visible error rather than silently skipping footage. A failed export can be retried after processing catches up. Multi-recording editing, burned-in subtitles, and a general provider onboarding UI are deferred.

## Boundaries and operations

- The schema is provider-independent; CPAC is the only discovery adapter currently implemented. Future audio/video providers need an adapter and verified timestamp/caption handling.
- This version targets CPAC's observed unencrypted, timestamp-anchored MPEG-TS HLS and embedded captions. It is not a general DASH, DRM, fragmented-MP4, or TTML ingest engine. Unsupported transport is rejected visibly.
- No automatic retention/purge task is installed. Keeping source plus language-specific playback media costs more than storing only one remux. At 720p, 2.4 Mbit/s video plus three 96 kbit/s audio tracks is roughly 29 GB per source stream-day before derived playback copies and overhead. Monitor bucket usage before prolonged capture.
- No deployment or production capture is performed by applying this change. Local tests use isolated databases and fake/local storage; a production R2/CORS/TIN pilot still needs to be run in the deployment environment.

## Verification

Use an isolated database suffix, following the repository's existing convention. Set `PGHOST` and `PGPORT` to your Lead-enabled PostgreSQL instance (`127.0.0.1:55433` for the current native setup, or port `55432` for the Docker example):

```sh
export PGHOST=127.0.0.1 PGPORT=55433
RAILS_ENV=test CONDUCTOR_WORKSPACE_NAME=cpac bin/rails db:create db:schema:load
RAILS_ENV=test CONDUCTOR_WORKSPACE_NAME=cpac PARALLEL_WORKERS=1 bin/rails test \
  test/models/warehouse/broadcast_media_test.rb \
  test/models/media_capture_state_test.rb test/models/media_clip_test.rb \
  test/models/broadcast_backfill_request_test.rb \
  test/services/warehouse/broadcasts test/jobs/warehouse/broadcasts \
  test/controllers/admin/broadcasts_controller_test.rb \
  test/controllers/admin/broadcast_backfills_controller_test.rb \
  test/controllers/admin/media_clips_controller_test.rb \
  test/services/search test/models/concerns/searchable_test.rb
```

Install and run the scoped JavaScript suite separately:

```sh
npm ci --prefix test/javascript
npm test --prefix test/javascript
```

Tests cover paginated historical discovery, backfill progress/recovery, subtitle-based clip selection, manifest parsing/discovery, source identity, lease fencing, replay, bilingual cue timing, transactional transcript search, remuxing/export, coverage gaps, admin/clip access, and broadcast editor DOM behavior. Real FFmpeg tests require `ffmpeg` and `ffprobe` on `PATH`. No cloud credentials are needed for the isolated suite.
