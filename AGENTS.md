## What is York Factory?

York Factory is Build Canada's backend repo. It powers the frontend (called TradingPost) and internal tools. 

We do a lot of data scraping and search indexing of open government data. All scraped data belongs under the `Warehouse` namespace and should be filed under the warehouse database. No private or application data should be stored in this database. 

It also includes a bilingual CMS API for Build Canada's website content and user management/interaction.


## Ruby/Rails conventions.

- For small jobs, prefer using [active_job-performs](https://github.com/kaspth/active_job-performs)

```
class Post < ApplicationRecord
  performs :publish
  # Or `performs def publish`!

  def publish
    # Some logic to publish a post
  end
end
```

- For jobs that need to run many small operations repeatedly (data scraping an index, ) use [Active Job Continuation](https://api.rubyonrails.org/classes/ActiveJob/Continuation.html) to create resumeable jobs. Read the docs when creating those kinds of jobs. 

## Infrastructure / Deploys

- We use kamal for deploying the repo, it lives on it's own OVH server.
- For search, we use turbopuffer as our index
- For our database, we use hosted postgres on planetscale.
- **Cloudflare R2** with separate buckets for archival (R2_BUCKET) and ActiveStorage (R2_ACTIVE_STORAGE_BUCKET)
