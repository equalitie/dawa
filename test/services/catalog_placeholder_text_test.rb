require "test_helper"

#
# Tests for the catalog placeholder text helper.
#
# This exists because placeholder prose is easy to get silently wrong: the callers only
# ever render it, and a short or single-paragraph result still "looks like text", so
# nothing fails. The paragraph count is asserted explicitly for that reason.
#
class CatalogPlaceholderTextTest < ActiveSupport::TestCase
  ##
  ## paragraphs
  ##

  test "paragraphs returns several paragraphs by default" do
    # Regression: the mock called this with count: 1, so the detail page's "long"
    # description rendered as a single paragraph and looked like it was truncating.
    text = CatalogPlaceholderText.paragraphs("peertube")

    assert_operator text.split("\n\n").size, :>, 1,
                    "a long description must be more than one paragraph"
  end

  test "paragraphs honours an explicit count" do
    assert_equal 3, CatalogPlaceholderText.paragraphs("peertube", count: 3).split("\n\n").size
    assert_equal 1, CatalogPlaceholderText.paragraphs("peertube", count: 1).split("\n\n").size
  end

  test "paragraphs separates paragraphs with a blank line" do
    # `simple_format` splits on blank lines. A single "\n" would collapse them into one
    # paragraph in the rendered HTML.
    text = CatalogPlaceholderText.paragraphs("peertube", count: 2)

    assert_includes text, "\n\n"
  end

  test "paragraphs returns non-empty prose" do
    text = CatalogPlaceholderText.paragraphs("peertube")

    assert text.present?
    refute_match(/\A\s*\z/, text)
    refute_includes text, "translation missing"
  end

  ##
  ## tagline
  ##

  test "tagline returns a single short sentence" do
    text = CatalogPlaceholderText.tagline("peertube")

    assert text.present?
    refute_includes text, "\n\n", "a tagline is one line of text"
  end

  ##
  ## determinism
  ##

  test "the same key always yields the same text" do
    # Screenshots and test expectations depend on this.
    assert_equal CatalogPlaceholderText.paragraphs("peertube"),
                 CatalogPlaceholderText.paragraphs("peertube")
    assert_equal CatalogPlaceholderText.tagline("peertube"),
                 CatalogPlaceholderText.tagline("peertube")
  end

  test "different keys yield different text" do
    refute_equal CatalogPlaceholderText.paragraphs("peertube"),
                 CatalogPlaceholderText.paragraphs("mastodon")
  end

  ##
  ## global RNG hygiene
  ##

  test "seeding does not leak into the global Faker RNG" do
    # Faker::Config.random is process-global. If it were left pinned, every other Faker
    # call in the app (including unrelated test fixtures) would silently become
    # deterministic, which is the kind of thing that only shows up as a confusing
    # intermittent failure much later.
    previous = Faker::Config.random
    CatalogPlaceholderText.paragraphs("peertube")

    assert_same previous, Faker::Config.random
  end

  test "text generated after a call is still random" do
    CatalogPlaceholderText.paragraphs("peertube")

    first = Faker::Lorem.sentence
    second = Faker::Lorem.sentence

    refute_equal first, second, "global Faker RNG must not be left seeded"
  end
end
