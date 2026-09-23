# Production rollout

This PR adds CPAC discovery/capture, historical backfills, bilingual transcript search, and clipping. It does not deploy the service or enable production captures. Fiber workers are outside this change; all jobs use the existing default queue.

## Before deploying

1. **Make TIN available on the PlanetScale Postgres branch.** The migration enables `tin` and builds the published transcript index concurrently. Verify availability and permissions before allowing the container entrypoint to migrate. If PlanetScale reports that only a superuser can create TIN, update the branch cluster as described in [PlanetScale search documentation](https://planetscale.com/docs/postgres/search), then retry. Lead is only for local development and CI; do not install it in production.

   ```sql
   SELECT name, default_version, installed_version
   FROM pg_available_extensions WHERE name = 'tin';
   CREATE EXTENSION IF NOT EXISTS tin;
   ```

2. **Check the existing R2 configuration.** No new required environment variables or provider API keys are introduced. Capture accepts `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, and `R2_BUCKET`, already listed in Kamal's secrets. It falls back to `credentials.r2`. Clip attachments use the existing `r2_active_storage` service, which currently reads encrypted `credentials.r2.endpoint`, `access_key_id`, `secret_access_key`, and `active_storage_bucket`; setting the environment variables alone does not configure that service. Keep archival and ActiveStorage buckets separate, with read/write permission to the appropriate bucket.

3. **Add browser CORS to the archival bucket.** Merge this rule into the bucket's existing CORS configuration; do not replace unrelated rules. Signed URLs do not bypass browser CORS. Keep the bucket private. See [Cloudflare's CORS documentation](https://developers.cloudflare.com/r2/buckets/cors/).

   ```json
   [{
     "AllowedOrigins": ["https://yorkfactory.buildcanada.com"],
     "AllowedMethods": ["GET", "HEAD"],
     "AllowedHeaders": ["Range"],
     "ExposeHeaders": ["Content-Length", "Content-Range", "Accept-Ranges", "ETag"],
     "MaxAgeSeconds": 3600
   }]
   ```

   Add any additional admin origins actually used. Rails' `CORS_ORIGINS` setting does not configure the R2 bucket.

4. **Deploy the rebuilt app image to web and workers.** The Dockerfile adds FFmpeg (including ffprobe); no manual host package installation is required for the container deployment. Run the three migrations `20260921000001` through `20260921000003` through the normal deployment process. They create five public-media tables in the warehouse schema, four operational tables in the primary schema, and the TIN index. Existing queue/cache schemas are unchanged.

## Enable and verify

- Kamal sets `CPAC_CAPTURE_ENABLED: "true"` in production. Discovery runs every 15 seconds and enables capture for newly discovered TV/event streams. This does not override existing stream pause settings; enable previously discovered streams individually in `/admin/broadcasts` as needed. Verify video, both subtitle languages, and a short clip export after deployment.
- Do not set `BROADCAST_STORAGE_SERVICE=local_archive` in production; that option is deliberately restricted to development/test.
- Confirm the existing worker and recurring scheduler are running. Discovery and capture recovery run every 15 seconds; historical backfill recovery runs every minute. Existing jobs and broadcasts share the default queue. No Solid Queue version or fiber configuration change is included.
- Allow outbound HTTPS to CPAC and the CDN hosts accepted by the provider adapter, plus R2. The browser also loads the pinned HLS.js import from jsDelivr; account for that origin if a Content Security Policy is configured.
- Check signed playback requests succeed in the production browser, both language searches return highlighted matches, and MP4/WebVTT downloads work. No Turbopuffer or embedding credentials are required for broadcast search; other search features retain their current configuration.
- Monitor capture lag, queue wait times, scratch disk, and archive growth before enabling more streams or bulk backfills. Downloads and FFmpeg commands occupy job slots while executing. There is no global encoder concurrency cap and no automatic retention policy in this version. Each precise export caps encoding threads at two, but several exports can still run simultaneously. Provision several GB of temporary disk per concurrent long export.

## Pause and rollback

Pause enabled live streams in the dashboard before stopping workers. Pausing live capture does not cancel previously queued historical requests or clip exports; account for those jobs before rolling back application code. Keep the additive tables and archived objects during an application rollback. Do not run destructive down migrations against captured data as a routine rollback procedure.

Production credentials, cluster state, R2 CORS, and capacity have not been inspected or changed by this PR. Complete the checks above in the deployment environment.
