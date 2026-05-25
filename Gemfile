source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "mission_control-jobs"
gem "propshaft"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Pipeline logic as associated objects on models
gem "active_record-associated_object"

# Auto-generate job classes from method definitions
gem "active_job-performs"

# R2/S3-compatible object storage
gem "aws-sdk-s3"

# PostGIS spatial database support
gem "activerecord-postgis-adapter"
gem "rgeo", "~> 3.1"
gem "rgeo-proj4", github: "rgeo/rgeo-proj4", branch: "master"
gem "rgeo-shapefile"
gem "rubyzip"

# CSV parsing (removed from Ruby 3.4 default gems)
gem "csv"

# RSS parsing (removed from Ruby 3.4 default gems)
gem "rss"

# HTTP client for fetching CSVs
gem "httpx"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

# Load .env files in development/test
gem "dotenv-rails", groups: [ :development, :test ]

# CMS: i18n with column backend
gem "mobility", "~> 1.3"

# CMS: lightweight pagination
gem "pagy", "~> 43.4"

# CMS: authentication
gem "devise"
gem "devise-jwt"

# CMS: slug generation with history
gem "friendly_id", "~> 5.5"

# CMS: markdown editor + renderer
gem "marksmith"
gem "commonmarker"
gem "reverse_markdown"

# CMS: unified LLM interface for translations
gem "ruby_llm"

# Admin: Hotwire for admin pages
gem "turbo-rails"
gem "stimulus-rails"
gem "importmap-rails"

# CMS: Google OAuth
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"

# CMS: rate limiting
gem "rack-attack"

# CMS: sanitize HTML input
gem "rails-html-sanitizer"

# Metrics: Excel file parsing for LinkedIn exports
gem "roo"
gem "roo-xls"

# One-shot SQLite reader for KPI v1 snapshot import
gem "sqlite3", require: false

# CMS: ActiveStorage variants
gem "image_processing"
gem "ruby-vips"

group :development, :test do
  # Compact error pages optimized for AI agents
  gem "concise_errors"

  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end
