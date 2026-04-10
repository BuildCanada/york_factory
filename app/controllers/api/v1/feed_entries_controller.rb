module Api
  module V1
    class FeedEntriesController < CmsBaseController
      ITEM_TYPE_MAP = {
        "x" => "SocialPost::X",
        "ig" => [ "SocialPost::Instagram", "SocialPost::InstagramReel" ],
        "tiktok" => "SocialPost::TikTok",
        "substack" => "SubstackPost",
        "memo" => "Memo",
        "blog" => "Post",
        "builder" => "Builder"
      }.freeze

      def index
        scope = FeedEntry.published.chronological.includes(:feedable)
        scope = apply_type_filter(scope, params[:type]) if params[:type].present?
        scope = scope.featured if params[:featured].present?

        pagy, entries = pagy(scope, limit: (params[:per_page] || 20).to_i.clamp(1, 100))
        render json: {
          data: entries.map { |e| serialize_entry(e) },
          pagination: pagy_metadata(pagy)
        }
      end

      def show
        entry = FeedEntry.find(params[:id])
        render json: serialize_entry(entry, full: true)
      end

      # Returns one entry per type for the homepage feed preview
      def picks
        pick_types = (params[:types] || "x,x:canada_spends,substack,memo").split(",")
        entries = pick_types.filter_map do |type_spec|
          pick_entry(type_spec.strip.downcase)
        end

        render json: { data: entries.map { |e| serialize_entry(e) } }
      end

      private

      # Supports: "x", "x:canada_spends", "memo|blog|builder"
      def pick_entry(type_spec)
        parts = type_spec.split("|")
        all_feedable_types = []
        account = nil

        parts.each do |part|
          type, acct = part.split(":", 2)
          account = acct if acct.present?
          all_feedable_types.concat(Array(ITEM_TYPE_MAP[type]))
        end

        return if all_feedable_types.empty?

        scope = FeedEntry.published.chronological
          .where(feedable_type: all_feedable_types)
          .includes(:feedable)

        if account.present?
          feedable_ids = SocialPost.where(account_handle: "@#{account}").select(:id)
          scope = scope.where(feedable_id: feedable_ids)
        end

        scope.first
      end

      def apply_type_filter(scope, type)
        feedable_types = ITEM_TYPE_MAP[type.downcase]
        return scope unless feedable_types

        scope.where(feedable_type: Array(feedable_types))
      end

      def serialize_entry(entry, full: false)
        feedable = entry.feedable
        data = {
          id: entry.id,
          feedable_type: entry.feedable_type,
          item_type: feedable.class.feed_type_label,
          published_at: entry.published_at,
          featured: entry.featured,
          tags: entry.tags
        }

        data.merge!(serialize_feedable(feedable, full: full))
        data
      end

      def serialize_feedable(feedable, full: false)
        case feedable
        when SocialPost
          serialize_social_post(feedable, full: full)
        when SubstackPost
          serialize_substack_post(feedable, full: full)
        when Memo
          serialize_memo_for_feed(feedable, full: full)
        when Post
          serialize_post_for_feed(feedable, full: full)
        when Builder
          serialize_builder_for_feed(feedable, full: full)
        else
          {}
        end
      end

      def serialize_social_post(post, full: false)
        data = {
          title: post.title,
          subtitle: post.body&.truncate(160),
          body: post.body,
          author: post.author_name,
          account_handle: post.account_handle,
          url: post.url,
          image_url: image_url(post.image),
          author_photo_url: image_url(post.avatar)
        }
        if full
          data[:embed_code] = post.embed_code
        end
        data
      end

      def serialize_substack_post(post, full: false)
        data = {
          title: post.title,
          subtitle: post.subtitle,
          author: post.author_name,
          url: post.external_url,
          image_url: image_url(post.image)
        }
        if full
          data[:body] = post.body
          data[:author_photo_url] = nil
        end
        data
      end

      def serialize_memo_for_feed(memo, full: false)
        data = {
          title: memo.title,
          subtitle: memo.category,
          author: memo.author&.name,
          url: nil,
          image_url: image_url(memo.seo_image),
          slug: memo.slug
        }
        if full
          data[:body] = memo.body.to_s
          data[:author_photo_url] = memo.author ? image_url(memo.author.profile_photo) : nil
        end
        data
      end

      def serialize_post_for_feed(post, full: false)
        data = {
          title: post.title,
          subtitle: post.summary,
          author: nil,
          url: nil,
          image_url: image_url(post.seo_image),
          slug: post.slug
        }
        if full
          data[:body] = post.body.to_s
          data[:author_photo_url] = nil
        end
        data
      end

      def serialize_builder_for_feed(builder, full: false)
        data = {
          title: builder.title,
          subtitle: builder.byline,
          author: nil,
          url: nil,
          image_url: image_url(builder.image),
          slug: builder.slug
        }
        if full
          data[:body] = builder.body.to_s
          data[:author_photo_url] = nil
        end
        data
      end
    end
  end
end
