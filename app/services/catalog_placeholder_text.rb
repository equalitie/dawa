#
# Placeholder text for catalog metadata the backend does not send yet.
#
# The catalog contract (docs/dcommsctl-api-requests.md, notes/TODO.md "App catalog
# metadata: real version, description, icon") includes prose and release history that
# dcommsctl does not return today. Building the UI against the intended shape means
# rendering something in those gaps, and the risk is that filler gets mistaken for real
# data -- by a reviewer, a screenshot, or a later developer who assumes the API works.
#
# So this class exists to make the gap explicit and centrally reversible:
#
#   * every caller can mark what it rendered as a placeholder
#   * generation is seeded from a key, so the same entry always produces the same text
#     and tests/screenshots stay stable
#   * when the real fields land, this file is deleted and the callers simplify
#
# It does NOT decide whether data is missing -- the value objects own that (`described?`,
# `long_described?`, `released_versions?`). This only fills a known gap.
#
class CatalogPlaceholderText
  # Paragraphs in the default long description. The detail page shows this in place of a
  # real description, so it needs enough body to read as prose rather than a stub.
  DEFAULT_PARAGRAPH_COUNT = 5

  # A sentence describing what an app is for.
  def self.tagline(key)
    fake(key) { |lorem| lorem.sentence }
  end

  #
  # Prose for the long description on the detail page.
  #
  # `Faker::Lorem.paragraphs` takes an options hash (not positional args) and returns an
  # array, so join it into prose. Paragraphs must be separated by a blank line because
  # `simple_format` splits on blank lines; a single "\n" would collapse them into one
  # paragraph in the rendered HTML.
  #
  def self.paragraphs(key, count: DEFAULT_PARAGRAPH_COUNT)
    fake(key) { |lorem| Array(lorem.paragraphs(number: count)).join("\n\n") }
  end

  #
  # Faker text seeded by `key`.
  #
  # Faker::Config.random is process-global, so it is restored afterwards. Leaving it
  # pinned would silently make every other Faker call in the process deterministic too,
  # including in tests that use Faker for unrelated fixtures.
  #
  def self.fake(key)
    previous = Faker::Config.random
    Faker::Config.random = Random.new(key.to_s.bytes.sum)
    yield(Faker::Lorem)
  ensure
    Faker::Config.random = previous
  end
  private_class_method :fake
end
