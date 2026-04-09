require "test_helper"

class TestimonialTest < ActiveSupport::TestCase
  setup { I18n.locale = :en }
  teardown { I18n.locale = :en }

  test "requires name" do
    t = Testimonial.new
    assert_not t.valid?
    assert_includes t.errors[:name], "can't be blank"
  end

  test "valid testimonial with name" do
    t = Testimonial.new(name: "Test Person")
    assert t.valid?
  end

  test "ordered scope sorts by position" do
    testimonials = Testimonial.ordered
    positions = testimonials.map(&:position).compact
    assert_equal positions, positions.sort
  end

  test "published scope excludes drafts" do
    published = Testimonial.published
    ids = published.pluck(:id)
    assert_not_includes ids, testimonials(:draft_testimonial).id
  end
end
