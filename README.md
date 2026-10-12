# York Factory

Automated pipeline that normalizes Canadian federal government fiscal data
(Public Accounts, Main Estimates, Supplementary Estimates) into shared,
queryable Postgres tables, plus a bilingual CMS API for Build Canada's website
content.

## Requirements

- Ruby (see `.ruby-version`)
- PostgreSQL with PostGIS
- [1Password CLI](https://developer.1password.com/docs/cli/) (`brew install 1password-cli`)
  with access to the **Engineering** vault

## Setup

```bash
bundle install
bin/rails credentials:setup   # fetch config/master.key from 1Password
bin/rails db:prepare          # create databases and load schemas
bin/rails db:seed             # seed data sources
bin/rails cms:seed            # seed CMS development data (optional)
```

`credentials:setup` pulls the Rails master key from the "York Factory Master
Key" item in the Engineering vault. All other secrets (database, R2, Anthropic,
TLS) live in `config/credentials.yml.enc` and are decrypted with that key —
no `.env` file needed.

## Running

```bash
bin/rails server              # API
bin/jobs                      # Solid Queue worker (translations, pipeline jobs)
```

## Tests

```bash
bin/rails test
```

## Deployment

Deploys go to an OVH VPS with [Kamal](https://kamal-deploy.org) (`config/deploy.yml`).
To deploy you need:

1. Your SSH public key on the server. An existing dev grants (or revokes) access with:

   ```bash
   bin/rails server:add_key GITHUB=username      # or KEY=/path/to/key.pub
   bin/rails server:remove_key MATCH=username    # refuses to remove your own key
   bin/rails server:list_keys
   ```
2. `config/master.key` (run `bin/rails credentials:setup`) — all deploy secrets
   are resolved from Rails credentials via `.kamal/secrets`
3. `kamal.registry_username` and `kamal.registry_password` in Rails credentials.
   The password must be a GitHub token with `read:packages` and
   `write:packages` access to the BuildCanada organization. Deploy images are
   stored in GHCR so the server can pull the same image after the deploy run.

Then, from pushed `main`:

```bash
bin/kamal deploy
```

Note: the builder targets `amd64`, so the first build on Apple Silicon
cross-compiles and is slow; subsequent builds are cached.

Pushes to `main` are deployed automatically only after the repository's `CI`
workflow succeeds. The deployment checks out and deploys the exact commit SHA
tested by that CI run. Kamal starts the web role and completes `db:prepare`
before starting the worker role. Configure a protected `production` GitHub
environment with these secrets:

- `RAILS_MASTER_KEY` — the contents of `config/master.key`
- `SSH_PRIVATE_KEY` — an unencrypted private key authorized for the `ubuntu`
  user on the deployment server
- `SSH_KNOWN_HOSTS` — the verified `known_hosts` entry for `66.70.179.6`

The Rails credentials unlocked by `RAILS_MASTER_KEY` must also contain the
`kamal.registry_username` and `kamal.registry_password` values described above.
Environment protection rules and required reviewers can be configured on the
GitHub `production` environment.

After a successful deploy, the workflow attempts to create a PostHog
error-tracking release for the deployed commit. This reporting step is
non-blocking: if it fails, the workflow summary warns that production deployed
successfully but release registration must be retried. To enable it, configure
`posthog.project_id` and a `posthog.personal_api_key` with
`error_tracking:read` and `error_tracking:write` access in Rails credentials.
For PostHog EU Cloud, set `posthog.api_host` to `https://eu.posthog.com`; it
defaults to US Cloud.
