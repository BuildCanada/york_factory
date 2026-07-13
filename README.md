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
3. Docker running locally, with a local registry on port 5555:

   ```bash
   docker run -d -p 127.0.0.1:5555:5000 --restart always --name kamal-registry registry:2
   ```

Then, from pushed `main`:

```bash
bin/kamal deploy
```

Note: the builder targets `amd64`, so the first build on Apple Silicon
cross-compiles and is slow; subsequent builds are cached.
