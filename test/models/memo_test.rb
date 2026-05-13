require "test_helper"

class MemoTest < ActiveSupport::TestCase
  setup do
    I18n.locale = :en
  end

  teardown do
    I18n.locale = I18n.default_locale
  end

  test "requires a slug" do
    memo = Memo.new
    assert_not memo.valid?
    assert memo.errors.where(:slug, :blank).any?, "expected a blank error on slug"
  end

  test "slug is not auto-generated from title_en" do
    memo = Memo.new(title_en: "My Policy Memo")
    memo.valid?
    assert_nil memo.slug
    assert memo.errors.where(:slug, :blank).any?
  end

  test "submitted slug is preserved verbatim" do
    memo = Memo.new(title_en: "Has Title", slug: "custom-slug", category: "housing")
    assert memo.save
    assert_equal "custom-slug", memo.reload.slug
  end

  test "slug uniqueness is enforced" do
    memo = Memo.new(
      slug: memos(:published_memo).slug,
      title_en: "Duplicate"
    )
    assert_not memo.valid?
    assert_includes memo.errors[:slug], "has already been taken"
  end

  test "category must be in allowed list" do
    memo = Memo.new(
      title_en: "Test",
      category: "invalid-category"
    )
    assert_not memo.valid?
    assert_includes memo.errors[:category], "is not included in the list"
  end

  test "nil category is valid" do
    memo = Memo.new(
      title_en: "No Category Memo",
      category: nil
    )
    memo.valid?
    assert_empty memo.errors[:category]
  end

  test "published scope returns only memos with past published_at" do
    published = Memo.published
    assert_includes published, memos(:published_memo)
    assert_not_includes published, memos(:draft_memo)
  end

  test "featured scope returns featured memos" do
    featured = Memo.featured
    assert_includes featured, memos(:published_memo)
    assert_not_includes featured, memos(:draft_memo)
  end

  test "by_category scope filters by category" do
    housing = Memo.by_category("housing")
    assert_includes housing, memos(:published_memo)
    assert_not_includes housing, memos(:draft_memo)
  end

  test "search scope matches on English title" do
    results = Memo.search("Housing Crisis")
    assert_includes results, memos(:published_memo)
  end

  test "search scope is case insensitive" do
    results = Memo.search("housing crisis")
    assert_includes results, memos(:published_memo)
  end

  test "search scope returns no results for unmatched query" do
    results = Memo.search("zzznomatch")
    assert_empty results
  end

  test "belongs to author" do
    memo = memos(:published_memo)
    assert_equal team_members(:alice), memo.author
  end

  test "author is optional" do
    memo = memos(:draft_memo)
    assert_nil memo.author
  end

  test "publication must be in allowed list" do
    memo = Memo.new(title_en: "X", publication: "nope")
    assert_not memo.valid?
    assert_includes memo.errors[:publication], "is not included in the list"
  end

  test "nil publication is valid" do
    memo = Memo.new(title_en: "Y", publication: nil)
    memo.valid?
    assert_empty memo.errors[:publication]
  end

  test "without_publication scope excludes tagged memos" do
    results = Memo.without_publication
    assert_includes results, memos(:published_memo)
    assert_not_includes results, memos(:build_toronto_memo)
  end

  test "by_publication scope includes only matching publication" do
    results = Memo.by_publication("build_toronto")
    assert_includes results, memos(:build_toronto_memo)
    assert_not_includes results, memos(:published_memo)
  end

  test "slug uniqueness is scoped by publication" do
    memo = Memo.new(
      slug: memos(:published_memo).slug,
      title_en: "Same slug, different publication",
      publication: "build_toronto"
    )
    assert memo.valid?, memo.errors.full_messages.to_sentence
  end

  test "slug uniqueness still enforced within same publication" do
    memo = Memo.new(
      slug: memos(:build_toronto_memo).slug,
      title_en: "Dup",
      publication: "build_toronto"
    )
    assert_not memo.valid?
    assert_includes memo.errors[:slug], "has already been taken"
  end

  test "build_toronto memo does not create a feed entry" do
    memo = memos(:build_toronto_memo)
    memo.touch
    assert_nil memo.reload.feed_entry
  end

  test "Mobility reads correct locale with fallback" do
    memo = memos(:published_memo)
    I18n.locale = :en
    assert_equal "Housing Crisis Analysis", memo.title

    I18n.locale = :fr
    assert_equal "Analyse de la crise du logement", memo.title
  end
end
