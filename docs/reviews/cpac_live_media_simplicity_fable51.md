Review metadata: Claude Code, `claude-fable-5-1`, medium effort, run through tmux on 2026-09-21. Reviewed `docs/plans/cpac_live_media.md`. Design unchanged. Findings below are the reviewer’s output, followed by independent validation notes.

> Historical design/review artifact. The implemented data model and behavior are documented in [the broadcast README](../broadcasts/README.md); transcript search now uses TIN, and precise re-encoded clipping is implemented.

# Simplicity review: `docs/plans/cpac_live_media.md`

## Verdict

The design is correct about the hard parts (bilingual embedded captions, timestamp alignment, recovery after crashes, visible gaps) and should keep them. It is over-built in the data model and operations layer: 10 tables, two parallel timelines (recording-relative microseconds plus UTC anchors), a generation-switch mechanism, a policy table, a lease table, and a gap table, most of which can be replaced by columns, existing repo mechanisms, or derived views without losing a stated requirement. A V1 with 5 warehouse tables and 1 application table meets every user requirement.

## Prioritized findings

**1. Use UTC wall-clock as the single timeline; drop recording-relative offsets (lines 34, 42, 86–90).**
The design stores `timeline_origin_at`, `start_us/end_us` per segment and cue, and PTS maps, then rebases cues for clips and enforces same-recording composite FKs so offsets line up. Lines 22 and 86 already establish that tracks are aligned by program-date-time, not by sequence numbers. Make every segment, passage, and clip boundary a `timestamptz` (plus `clock_basis: provider|estimated` and raw PTS/time base per segment for the remuxer). Then "offsets never shift when an earlier segment appears" is automatic, cross-recording alignment is free, and cue rebasing becomes subtraction at export. Preserves synchronization; removes one coordinate system and the composite-FK requirement in line 52.

**2. Make `MediaRecording` a time window over a stream, not the owner of tracks and segments (lines 42–44, 90).**
Because CPAC TV rotates daily, the design invents overlap handling: straddling audio segments get "separate recording-local asset registrations" (line 90). If segments and tracks belong to the stream and a recording is `(stream, starts_at, ends_at)`, rotation is a row insert, straddling segments need no duplication, and playback for a window is a time-range query. Events still get one window. Tracks keyed by `(stream_id, track_key)` with first/last observed timestamps absorb mid-broadcast layout changes. Clips pin `(stream, tracks, start_at, end_at)` and V1 can still restrict a clip to one window.

**3. Collapse `MediaAsset` and `MediaSegment` into one archived-object table (lines 44–45).**
Every archived byte range is one R2 object; the design gives it a row in both tables. One `media_objects` table with `kind` (`source_segment`, `init`, `manifest`, `playback_part`, `caption_file`), optional track FK, object key, sha256, byte size, time range, epoch, media_sequence, PTS covers all of it. Keep the "only committed after upload succeeds" rule and deterministic keys; that is what makes retry safe, not the second table.

**4. Defer byte-range identity (line 44).**
The inspected manifests deliver whole segments. Unique on `(track_id, epoch, media_sequence)`. If a byte-range provider appears, each fetched range becomes its own object with its own sequence; no sentinel columns needed now.

**5. Store cues as WebVTT objects, keep only passages in Postgres (lines 46–47, 50, 105).**
Line 105 already requires WebVTT caption tracks for the archived HLS presentation. That file is the cue evidence; a 100k-row-per-day cue table duplicates it. The passage table remains the `Searchable` unit and carries the timestamps the dashboard needs for click-to-seek. Roll-up de-duplication happens in the passage builder reading VTT. Clip sidecars intersect the VTT directly. Tradeoff: no SQL over individual cues. Acceptable because raw transport is retained (line 103) and cues can always be regenerated.

**6. Drop `generation`/`current_generation`; reuse `Searchable` revision semantics (lines 46–47, 50, 119).**
`Searchable#prepare_search_sync!` already bumps `search_revision` when `search_content_hash` changes and no-ops when it doesn't, and `withdrawn_from_search?` deletes stale index rows. With deterministic `window_key`, a re-extraction is: rebuild passages in one transaction, upsert by key, withdraw keys that vanished. No pointer switch, no retired-generation filtering at hydration. Partial builds are avoided by the transaction, not by a second column. Note that the passage model must be added to `Searchable::MODEL_NAMES` and a `Search::Realms::Broadcasts` class registered; the plan mentions the realm but not the model list.

**7. Replace `MediaCapturePolicy` and `MediaCaptureRun` with columns and existing job controls (lines 58–59, 62, 111).**
`Warehouse::MediaFeed` already stores `enabled`, `cadence_seconds`, `next_fetch_at`, `consecutive_failures`, and `MediaFeedFetch` run records live in Warehouse. That is the repo's precedent: operational state about public scraping is Warehouse data, not private data. Put `capture_enabled`, `next_poll_at`, `lease_expires_at`, `cursor` (JSONB per track), `consecutive_failures` on `media_streams`. Mutual exclusion comes from Solid Queue's `limits_concurrency` keyed on the stream, exactly as `Warehouse::Source::Fetcher::FetchJob` does today. Rendition ceiling and concurrency caps belong in Rails config. This also eliminates the cross-schema FK the design itself calls fragile (line 62). The only application table left is `MediaClip`, which is genuinely user-owned.

**8. Don't reuse `Warehouse::Source` for stream identity (line 40).**
`Source` means "a fetch-frequency-driven file download producing `RawIngestion`s" via `has_object :fetcher` and a strategy registry. The design bypasses all of that and keeps only the FK. `MediaFeed` doesn't use `Source` either. A `provider` string column on `media_streams`, validated against an allowlist like `MediaFeed::STRATEGIES`, is the convention-consistent choice and avoids `automatically_scraped?` returning nonsense.

**9. Be honest about queue topology (lines 111–113).**
A ~3-second poll per stream plus 15-second discovery, implemented as self-rescheduling jobs on a queue with 3 threads per process shared with every other job in the app, is not the design's real risk; the real risk is that `config/queue.yml` forbids the only clean fix. `ActiveJob::Continuation` is for resumable batches, not a live-edge loop, and nothing in the repo uses it yet. Say plainly that V1 needs `JOB_CONCURRENCY` raised or a topology decision before pilot. Also consider, during the spike, letting FFmpeg's HLS demuxer follow the live edge in stream-copy mode while Ruby supervises the process and registers emitted objects; it removes most hand-written HLS state machinery. Only adopt it if the spike confirms the emitted TS retains the A53 caption data byte-for-byte, since line 105 rightly demands original evidence.

**10. Derive gaps instead of storing them (line 48).**
Missing sequence numbers and time holes fall out of the object ledger; caption absence falls out of passage coverage. Compute on read, indexed by `(track_id, starts_at)`. Persist only what cannot be derived: an unrecoverable alignment reset, recorded as the epoch increment plus `state: partial` and a `gap_summary` JSONB written at finalize. Tradeoff: live gap display for an open recording is a query rather than a lookup, which is fine at 57,600 rows per stream-day.

## Recommended minimal V1

Warehouse (`Warehouse::*`, bigint IDs, string enums with CHECK constraints per repo convention):

| Table | Purpose |
|---|---|
| `media_streams` | provider, external_id, kind, bilingual titles/URLs, manifest_url, provider_state, capture_enabled, next_poll_at, lease_expires_at, cursor JSONB, consecutive_failures |
| `media_tracks` | stream FK, track_key, kind, language, role, carrier_track_id for embedded captions, selector, codec, first/last observed at |
| `media_objects` | stream FK, optional track FK, kind, epoch, media_sequence, object_key, sha256, byte_size, starts_at, ends_at, clock_basis, PTS/time base, availability |
| `media_recordings` | stream FK, starts_at, ends_at, state (`open`, `finalized`, `partial`), gap_summary JSONB, snapshotted titles |
| `media_transcript_passages` | track FK, window_key, starts_at, ends_at, text, plus `Searchable` columns |

Application: `MediaClip` (user FK, stream and recording IDs, track selections, requested and actual boundaries, mode, state, ActiveStorage attachment, pinned object digests).

Pipeline, using `has_object` associated objects on `MediaStream` and `performs` for small entry points: `Discoverer` (15s, claims due streams with `FOR UPDATE SKIP LOCKED` like `DispatchDueFeedsJob`), `Capturer` (bounded run under `limits_concurrency`, upload then commit), `Extractor` (stateful 608/708 decode across segment boundaries, writes VTT objects and passages), `Packager` (60s fMP4 parts, archived HLS with VTT), `Searchable` sync, `MediaClip::Exporter`.

## Defer

Byte-range HLS identity, `MediaGap` table, cue table, generation pointers, `MediaCapturePolicy`, monthly partitions, compaction, VOD backfill, multi-recording clips, exact-mode transcoding (ship fast copy first and display requested versus actual boundaries).

## Essential complexity to keep

- Decode both caption fields, not only advertised CC1; language attribution with `und` fallback; missing-language shown as unavailable, never machine translated (lines 24, 28, 103).
- Stateful caption decoder with replay from a safe boundary after restart.
- Epoch increment on sequence-namespace reset; `partial` state when alignment cannot be recovered.
- Upload-before-commit with deterministic keys and a reconciliation task for orphaned uploads.
- Per-stage freshness timestamps (video, each caption language, playback, search) so a healthy video download cannot hide stalled French extraction.
- Retain original transport files; the remux is not the evidence.
- Explicit copy-versus-exact clip semantics with verified output boundaries.
- A dedicated `broadcasts` realm rather than reusing `media`, whose publisher allowlist would reject CPAC.

---

## Independent validation notes (Codex)

The review contains useful simplifications, but these claims should not be accepted as verified implementation facts:

- Finding 9 says the repository does not use Active Job Continuation. It does: `app/jobs/warehouse/sync_spending_ingestion_job.rb:2` and `app/jobs/warehouse/extract_municipal_financial_statements_job.rb:2` both include `ActiveJob::Continuable`.
- Finding 6 says `Searchable#prepare_search_sync!` is a no-op for unchanged content. It preserves the revision, but still allocates an index sequence, clears `search_synced_at`, and the caller performs embedding/index work. See `app/models/concerns/searchable.rb:139`. A Postgres transaction also cannot make Turbopuffer changes atomic; retiring stale passages still needs a reliable indexing strategy.
- Finding 1’s UTC-only timeline is a proposal, not a proven simplification for all future sources. Audio files and other on-demand inputs may lack authoritative wall-clock anchors. Native PTS mapping and explicit handling of discontinuities remain necessary, and same-owner validation remains useful regardless of timestamp representation.
- Finding 7 correctly identifies existing `limits_concurrency` usage in `app/models/warehouse/source/fetcher.rb:5`. It does not establish that expiring job concurrency controls alone fence stale workers. The final capture design must handle a worker continuing after its lease expires. Existing warehouse operational columns also do not override the user’s instruction to keep application data outside the warehouse.
- Finding 10’s suggestion to derive caption absence from passage coverage cannot distinguish missing captions from legitimate silence. Keep observed transport/service availability evidence even if a dedicated gap table is removed.
- The proposed FFmpeg-supervised capture alternative is explicitly a spike: it has not been shown to preserve original source bytes, all language tracks, or recovery behavior. Do not substitute it for the source ledger without that verification.

Recommended candidates for the next design revision: merge asset/segment metadata; treat recordings as archive windows to simplify daily boundaries; evaluate immutable WebVTT plus searchable passages instead of SQL cue rows; defer exact clipping and configurable policy UI. Resolve timeline, recovery, and cross-system indexing guarantees before adopting the more aggressive reductions.
