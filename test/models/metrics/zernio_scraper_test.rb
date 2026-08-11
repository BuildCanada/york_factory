require "test_helper"

class Metrics::ZernioScraperTest < ActiveSupport::TestCase
  FakeClient = Data.define(:responses, :requests) do
    def get(path, params: {})
      requests << [ path, params ]
      responses.fetch(path).deep_dup
    end
  end

  setup do
    @now = Time.zone.parse("2026-08-10 18:00:00 UTC")
    @account_payload = {
      "_id" => "account-twitter-build-canada",
      "profileId" => { "_id" => "profile-build-canada", "name" => "Build Canada" },
      "platform" => "twitter",
      "username" => "buildcanada",
      "displayName" => "Build Canada",
      "profileUrl" => "https://x.com/buildcanada",
      "enabled" => true,
      "adsStatus" => "connected",
      "followersCount" => 16_578,
      "followersLastUpdated" => "2026-08-10T03:53:05Z",
      "updatedAt" => "2026-08-10T16:34:15Z"
    }
    @post_payload = {
      "_id" => "zernio-post-1",
      "latePostId" => nil,
      "content" => "Great news for Canadian builders!",
      "publishedAt" => "2026-08-09T18:00:00Z",
      "scheduledFor" => "2026-08-09T18:00:00Z",
      "status" => "published",
      "isExternal" => true,
      "isAd" => false,
      "profileId" => "profile-build-canada",
      "mediaItems" => [],
      "platforms" => [ {
        "platform" => "twitter",
        "status" => "published",
        "platformPostId" => social_posts(:x_post).external_id,
        "accountId" => "account-twitter-build-canada",
        "accountUsername" => "buildcanada",
        "platformPostUrl" => social_posts(:x_post).url,
        "analytics" => {
          "impressions" => 1_200,
          "likes" => 42,
          "comments" => 3,
          "engagementRate" => 3.75,
          "lastUpdated" => "2026-08-10 17:45:00"
        }
      } ]
    }
  end

  test "imports accounts, links legacy metrics, and records follower history" do
    legacy_stat = Metrics::TwitterStat.create!(account: "build_canada", date: Date.new(2026, 8, 10))
    scraper = scraper_for(accounts_response)

    assert_difference -> { Metrics::SocialMediaAccount.count }, 1 do
      assert_difference -> { Metrics::SocialMediaAccountMetricSnapshot.count }, 1 do
        scraper.sync_accounts!
      end
    end

    account = Metrics::SocialMediaAccount.find_by!(zernio_account_id: "account-twitter-build-canada")
    assert_equal "build_canada", account.account_key
    assert_equal 16_578, account.metric_snapshots.sole.followers_count
    assert_equal account, legacy_stat.reload.social_media_account
  end

  test "imports platforms that do not have a legacy metrics table" do
    @account_payload.merge!(
      "_id" => "account-bluesky-build-canada",
      "platform" => "bluesky",
      "username" => "buildcanada.com"
    )

    assert_difference -> { Metrics::SocialMediaAccount.count }, 1 do
      scraper_for(accounts_response).sync_accounts!
    end
  end

  test "imports post metrics and links a matching social post" do
    scraper = scraper_for(accounts_response)
    scraper.sync_accounts!
    client = fake_client("/analytics" => analytics_response)
    scraper = described_scraper(client)

    result = scraper.sync_page!(page: 1)

    assert_equal({ processed: 1, total: 101, next_page: 2 }, result)
    post = Metrics::SocialMediaPost.find_by!(zernio_post_id: "zernio-post-1")
    assert_equal social_posts(:x_post), post.social_post
    assert post.external?
    assert_equal 1_200, post.latest_metric_snapshot.impressions
    assert_equal 42, post.latest_metric_snapshot.likes
    assert_equal BigDecimal("3.75"), post.latest_metric_snapshot.engagement_rate
    assert_equal "/analytics", client.requests.sole.first
    assert_equal 100, client.requests.sole.last[:limit]
    assert_equal "all", client.requests.sole.last[:source]
  end

  test "does not touch timestamps when an observation is unchanged" do
    scraper = scraper_for(accounts_response)
    scraper.sync_accounts!
    scraper = scraper_for(analytics_response, path: "/analytics")
    scraper.sync_page!(page: 1)

    post = Metrics::SocialMediaPost.find_by!(zernio_post_id: "zernio-post-1")
    snapshot = post.metric_snapshots.sole
    stable_time = 1.day.ago
    post.update_column(:updated_at, stable_time)
    snapshot.update_column(:updated_at, stable_time)

    later_scraper = Metrics::ZernioScraper.new(
      client: fake_client("/analytics" => analytics_response),
      now: @now + 1.hour
    )
    later_scraper.sync_page!(page: 1)

    assert_equal 1, post.metric_snapshots.count
    assert_equal stable_time.to_i, post.reload.updated_at.to_i
    assert_equal stable_time.to_i, snapshot.reload.updated_at.to_i
    assert_equal @now.to_i, snapshot.scraped_at.to_i
  end

  test "updates the timestamp when metrics change without a new observation time" do
    scraper = scraper_for(accounts_response)
    scraper.sync_accounts!
    scraper_for(analytics_response, path: "/analytics").sync_page!(page: 1)
    snapshot = Metrics::SocialMediaPost.find_by!(zernio_post_id: "zernio-post-1").metric_snapshots.sole
    snapshot.update_column(:updated_at, 1.day.ago)
    @post_payload.dig("platforms", 0, "analytics")["likes"] = 43

    Metrics::ZernioScraper.new(
      client: fake_client("/analytics" => analytics_response),
      now: @now + 1.hour
    ).sync_page!(page: 1)

    assert_equal 43, snapshot.reload.likes
    assert_equal (@now + 1.hour).to_i, snapshot.scraped_at.to_i
    assert snapshot.updated_at > 1.minute.ago
  end

  test "imports ad accounts, campaigns, ads, and every daily analytics payload" do
    scraper_for(accounts_response).sync_accounts!
    account = Metrics::SocialMediaAccount.find_by!(zernio_account_id: "account-twitter-build-canada")

    described_scraper(fake_client(
      "/ads/accounts" => { "accounts" => [ ad_account_payload ] }
    )).sync_ad_account!(account_id: account.id)
    ad_account = account.ad_accounts.sole

    campaign_result = described_scraper(fake_client(
      "/ads/campaigns" => ad_campaigns_response
    )).sync_ad_campaigns_page!(page: 1)
    ad_result = described_scraper(fake_client(
      "/ads" => ads_response
    )).sync_ads_page!(page: 1)

    campaign = account.ad_campaigns.sole
    ad = account.ads.sole
    assert_nil campaign_result[:next_page]
    assert_nil ad_result[:next_page]
    assert_equal ad_account, campaign.ad_account
    assert_equal campaign, ad.campaign
    assert_equal "Website Drive", campaign.name
    assert_equal({ "headline" => "Build Canada" }, ad.creative_payload)
    assert_equal({ "platformOnly" => { "value" => 7 } }, ad.source_payload["customData"])

    analytics = { "analytics" => {
      "summary" => { "spend" => 12.5, "lastSyncedAt" => "2026-08-10T17:00:00Z" },
      "daily" => [ daily_ad_metric_payload ]
    } }
    described_scraper(fake_client(
      "/ads/timeline" => { "rows" => [ daily_ad_metric_payload ], "backfillPending" => true },
      "/ads/campaigns/campaign-1/analytics" => analytics,
      "/ads/zernio-ad-1/analytics" => analytics
    )).tap do |scraper|
      scraper.sync_ad_account_analytics!(id: ad_account.id)
      scraper.sync_ad_campaign_analytics!(id: campaign.id)
      scraper.sync_ad_analytics!(id: ad.id)
    end

    [ ad_account.daily_metrics.sole, campaign.daily_metrics.sole, ad.daily_metrics.sole ].each do |metric|
      assert_equal BigDecimal("12.5"), metric.spend
      assert_equal 1000, metric.impressions
      assert_equal BigDecimal("3.4"), metric.conversions
      assert_equal({ "signup" => 3 }, metric.source_payload["actions"])
    end
    assert ad_account.reload.backfill_pending?
    assert_equal BigDecimal("12.5"), campaign.reload.metrics_payload["spend"]
    assert_equal Time.zone.parse("2026-08-10T17:00:00Z"), ad.reload.last_synced_at
  end

  test "does not touch unchanged ad data timestamps" do
    scraper_for(accounts_response).sync_accounts!
    account = Metrics::SocialMediaAccount.find_by!(zernio_account_id: "account-twitter-build-canada")
    scraper = described_scraper(fake_client("/ads/accounts" => { "accounts" => [ ad_account_payload ] }))
    scraper.sync_ad_account!(account_id: account.id)
    ad_account = account.ad_accounts.sole
    analytics = { "rows" => [ daily_ad_metric_payload ] }
    described_scraper(fake_client("/ads/timeline" => analytics)).sync_ad_account_analytics!(id: ad_account.id)
    metric = ad_account.daily_metrics.sole
    stable_time = 1.day.ago
    ad_account.update_column(:updated_at, stable_time)
    metric.update_column(:updated_at, stable_time)

    Metrics::ZernioScraper.new(
      client: fake_client("/ads/timeline" => analytics), now: @now + 1.hour
    ).sync_ad_account_analytics!(id: ad_account.id)

    assert_equal stable_time.to_i, ad_account.reload.updated_at.to_i
    assert_equal stable_time.to_i, metric.reload.updated_at.to_i
  end

  private

  def accounts_response
    { "accounts" => [ @account_payload ], "hasAnalyticsAccess" => true }
  end

  def analytics_response
    {
      "posts" => [ @post_payload ],
      "pagination" => { "page" => 1, "limit" => 100, "total" => 101, "pages" => 2 }
    }
  end

  def ad_account_payload
    {
      "id" => "ad-account-1",
      "platform" => "google",
      "name" => "Build Canada Ads",
      "currency" => "CAD",
      "timezoneName" => "America/Toronto",
      "selectable" => true,
      "customProviderField" => "retained"
    }
  end

  def ad_campaigns_response
    {
      "campaigns" => [ {
        "accountId" => "account-twitter-build-canada",
        "platform" => "google",
        "platformCampaignId" => "campaign-1",
        "platformAdAccountId" => "ad-account-1",
        "campaignName" => "Website Drive",
        "status" => "active",
        "currency" => "CAD",
        "adCount" => 1,
        "metrics" => { "spend" => 12.5 },
        "providerCampaignField" => { "retained" => true }
      } ],
      "pagination" => { "page" => 1, "total" => 1, "pages" => 1 }
    }
  end

  def ads_response
    {
      "ads" => [ {
        "_id" => "zernio-ad-1",
        "accountId" => "account-twitter-build-canada",
        "platform" => "google",
        "platformAdId" => "platform-ad-1",
        "platformAdAccountId" => "ad-account-1",
        "platformCampaignId" => "campaign-1",
        "name" => "Real Photo Group",
        "status" => "active",
        "creative" => { "headline" => "Build Canada" },
        "customData" => { "platformOnly" => { "value" => 7 } }
      } ],
      "pagination" => { "page" => 1, "total" => 1, "pages" => 1 }
    }
  end

  def daily_ad_metric_payload
    {
      "date" => "2026-08-09",
      "spend" => 12.5,
      "impressions" => 1000,
      "clicks" => 50,
      "conversions" => 3.4,
      "ctr" => 5.0,
      "actions" => { "signup" => 3 },
      "videoMetrics" => { "views25Percent" => 100 }
    }
  end

  def scraper_for(response, path: "/accounts")
    described_scraper(fake_client(path => response))
  end

  def described_scraper(client)
    Metrics::ZernioScraper.new(client: client, now: @now)
  end

  def fake_client(responses)
    FakeClient.new(responses, [])
  end
end
