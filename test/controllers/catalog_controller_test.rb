require_relative "../test_helper"

#
# Integration tests for the read-only catalog.
#
# The adapter is stubbed so these run without a live dcommsctl. What matters here is not the
# transport (DcommsClient has its own tests) but the page's behaviour: it lists catalog
# entries, it tolerates a broken catalog, and it never 500s when the backend is unreachable.
#
class CatalogControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "catalog-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Replace the controller's adapter with a stub returning the given entries (or raising,
  # to exercise the unreachable path).
  #
  # The real `adapter` is aliased aside and restored afterwards. It must not be removed:
  # `remove_method` would drop the controller's own method for the rest of the process,
  # so any later test that exercises the real path fails with a confusing
  # "undefined local variable or method 'adapter'".
  #
  # `entry:` and `entry_raises:` drive the show action's single-entry lookup.
  def with_stubbed_adapter(entries: [], raises: nil, entry: nil, entry_raises: nil)
    fake = Object.new
    fake.define_singleton_method(:catalog_list) do
      raise raises if raises
      entries
    end
    fake.define_singleton_method(:catalog_entry) do |id:| # rubocop:disable Lint/UnusedBlockArgument
      raise entry_raises if entry_raises
      entry
    end

    CatalogController.alias_method(:adapter_without_stub, :adapter)
    CatalogController.define_method(:adapter) { fake }
    yield
  ensure
    CatalogController.alias_method(:adapter, :adapter_without_stub)
    CatalogController.send(:remove_method, :adapter_without_stub)
  end

  def entry(id: "peertube", name: "Peertube", version: nil, redirect_uri: nil, description: nil,
            long_description: nil, upstream_url: nil, definition_url: nil, updated_at: nil,
            releases: [])
    Dcomms::CatalogEntry.new(
      id: id, name: name, version: version, redirect_uri: redirect_uri,
      description: description, long_description: long_description,
      upstream_url: upstream_url, definition_url: definition_url,
      updated_at: updated_at, releases: releases
    )
  end

  def release(version: "1.0.0", released_at: nil, changelog: nil)
    Dcomms::Release.new(version: version, released_at: released_at, changelog: changelog)
  end

  #
  # access
  #

  test "index requires an admin" do
    get catalog_index_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  #
  # wiring
  #

  test "the real adapter is constructed, not stubbed away" do
    # Every other test here stubs `adapter`, which hides construction bugs: a default
    # DcommsAdapter with nil collaborators raises "undefined method ... for nil" on the first
    # request. This exercises the real path with no stub.
    #
    # The outcome deliberately does NOT depend on whether dcommsctl happens to be running:
    # it must render a page either way, never a 500. Asserting the error banner (as this once
    # did) made the test pass on a machine with no daemon and fail on one with a daemon.
    login_as(@user)
    get catalog_index_path

    assert_response :success
  end

  #
  # rendering
  #

  test "lists every entry from the catalog" do
    with_stubbed_adapter(entries: [
      entry(id: "peertube", name: "Peertube"),
      entry(id: "mastodon", name: "Mastodon")
    ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "body", text: /Peertube/
      assert_select "body", text: /Mastodon/
      assert_select "body", text: /peertube/
    end
  end

  test "renders each entry as a card, not a table" do
    with_stubbed_adapter(entries: [ entry(id: "peertube"), entry(id: "mastodon") ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select ".card", count: 2
      assert_select "table", count: 0
    end
  end

  test "each card identifies the catalog entry it shows" do
    with_stubbed_adapter(entries: [ entry(id: "peertube") ]) do
      login_as(@user)
      get catalog_index_path

      # The id is rendered, so a card is attributable to a catalog entry without
      # relying on the order of the grid.
      assert_select ".card code", text: "peertube"
    end
  end

  test "an unknown version renders as unknown, not as an empty cell" do
    # The live catalog returns version: "" for most entries. That means unknown, not broken,
    # and the page must say so.
    with_stubbed_adapter(entries: [ entry(id: "peertube", name: "Peertube", version: nil) ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "body", text: /Unknown/
    end
  end

  test "a known version is shown" do
    with_stubbed_adapter(entries: [ entry(id: "dawa", name: "DAWA", version: "0.0.1") ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "body", text: /0\.0\.1/
    end
  end

  #
  # resilience
  #

  test "unreachable backend shows a banner rather than raising" do
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "body", text: /no route to host/
    end
  end

  test "an empty catalog explains itself" do
    with_stubbed_adapter(entries: []) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "body", text: /No installable apps were found/
    end
  end

  test "a catalog that is empty because of an error does not claim it is empty" do
    with_stubbed_adapter(raises: DcommsClient::ProtocolError.new("garbage")) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_no_match(/No installable apps were found/, response.body)
    end
  end

  test "an error renders the banner and nothing else" do
    # The failure banner and the cards are mutually exclusive. Rendering an empty grid
    # underneath an error reads as "the catalog is empty" on top of "we could not reach the
    # backend", which are different claims.
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select ".card", count: 0, message: "no cards should render when the backend failed"
    end
  end

  test "a successful load renders the cards and no error banner" do
    with_stubbed_adapter(entries: [ entry ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select ".card", count: 1
      assert_select "div.alert-danger", count: 0
    end
  end

  #
  # card contents
  #

  test "a description from the backend is shown as-is, not as filler" do
    with_stubbed_adapter(entries: [ entry(description: "A federated video platform") ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "body", text: /A federated video platform/
    end
  end

  test "a missing description is filled in and flagged as a placeholder" do
    # The backend sends no description yet, so this is generated filler. It must be
    # marked, otherwise placeholder text would be indistinguishable from real data.
    with_stubbed_adapter(entries: [ entry ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "[data-placeholder='true']", count: 1
    end
  end

  test "a real description is not flagged as a placeholder" do
    with_stubbed_adapter(entries: [ entry(description: "A federated video platform") ]) do
      login_as(@user)
      get catalog_index_path

      assert_select "[data-placeholder='true']", count: 0
    end
  end

  test "the updated date is shown when the backend sends one" do
    with_stubbed_adapter(entries: [ entry(updated_at: "2026-03-04T10:00:00Z") ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_select "body", text: /Updated Mar +4 2026/
    end
  end

  test "no updated date is rendered when the backend sends none" do
    # Most of the live catalog has no timestamp. An empty cell would read as a bug;
    # omitting the line is the honest rendering.
    with_stubbed_adapter(entries: [ entry ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_no_match(/Updated/, response.body)
    end
  end

  test "the version is labelled, not a bare number" do
    with_stubbed_adapter(entries: [ entry(version: "1.2.3") ]) do
      login_as(@user)
      get catalog_index_path

      assert_select "body", text: /Version 1\.2\.3/
    end
  end

  #
  # catalog vs installed apps
  #

  test "the catalog shows no install or lifecycle actions" do
    # This page is read-only. Installing creates an app, which is a separate concern;
    # offering the action here would conflate the two.
    with_stubbed_adapter(entries: [ entry ]) do
      login_as(@user)
      get catalog_index_path

      assert_response :success
      assert_no_match(/Uninstall/, response.body)
      assert_no_match(/Restart/, response.body)
    end
  end

  test "the catalog index is reachable and the full resource set is routed" do
    # Full RESTful routes are declared for :catalog deliberately, so the index is reachable
    # and the rest of the resource set is reserved for later work. This asserts the index
    # route exists and resolves, not that the resource is minimal.
    assert_equal "/catalog", Rails.application.routes.url_helpers.catalog_index_path
    assert_routing({ method: "get", path: "/catalog" },
                   { controller: "catalog", action: "index" })
  end

  #
  # show
  #

  test "show requires an admin" do
    get catalog_path("peertube")
    assert_response :redirect
    assert_redirected_to login_path
  end

  test "show requests the entry named in the path" do
    requested = nil
    with_stubbed_adapter(entry: entry(name: "Peertube")) do
      requested = :called
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
    end
    assert_equal :called, requested
  end

  test "show renders the entry name, id, and version" do
    with_stubbed_adapter(entry: entry(name: "Peertube", version: "7.0.0")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "body", text: /Peertube/
      assert_select "body", text: /peertube/
      assert_select "body", text: /7\.0\.0/
    end
  end

  test "show has no missing translations" do
    # `t` renders a visible "translation missing" span rather than raising, so a typo in a
    # locale key ships silently. Assert it directly.
    with_stubbed_adapter(entry: entry(version: "7.0.0", updated_at: "2026-03-04T10:00:00Z",
                                       releases: [ release ])) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_no_match(/translation missing/, response.body)
    end
  end

  test "show leaks no Haml markup into the output" do
    # A stray `=` in an attribute position turns into literal text, which renders on the
    # page and passes every content assertion that does not look for it.
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get catalog_path("peertube")

      assert_no_match(/= t\(/, response.body)
      assert_no_match(/translation_missing/, response.body)
    end
  end

  test "the entry name is a heading, not the box colour" do
    # v.box's first positional arg is the COLOUR, not a title. Passing a name there yields
    # a nonsense class like "text-bg-Peertube" and no visible name.
    with_stubbed_adapter(entry: entry(name: "Peertube")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select "h3", text: "Peertube"
      assert_select "[class*='text-bg-Peertube']", count: 0
    end
  end

  test "show renders the install button" do
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "button", text: /Install/
    end
  end

  test "the install button is disabled because it is not wired up" do
    # Installing creates an app, a separate resource that does not exist yet. A live
    # button that silently does nothing is worse than an obviously disabled one.
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select "button[disabled]", text: /Install/
    end
  end

  test "the install button carries no action" do
    # Guards against the button being wired to a route that does not exist yet. A data
    # attribute or form action here would mean something is listening for clicks.
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select "button", text: /Install/ do |elements|
        element = elements.first
        assert_nil element["form"], "install button must not submit a form"
        refute_includes element["data"].to_s, "action", "install button must not have a click action"
      end
    end
  end

  test "the install button is not a link or a form" do
    # Scope to the header box: the page chrome contains links (breadcrumbs, sidebar) and
    # the layout renders a logout form on every page, so a page-wide count asserts the
    # wrong thing.
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select ".card-body a", count: 0
      assert_select ".card-body form", count: 0
    end
  end

  #
  # show: described fields
  #

  test "show renders the long description when the backend sends one" do
    with_stubbed_adapter(entry: entry(long_description: "A federated video platform.")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "body", text: /A federated video platform/
      assert_select "[data-placeholder='true']", count: 0
    end
  end

  test "show fills a missing long description and marks it as a placeholder" do
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "[data-placeholder='true']", count: 1
    end
  end

  test "show links to the upstream project" do
    with_stubbed_adapter(entry: entry(upstream_url: "https://joinpeertube.org")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select "a[href='https://joinpeertube.org']"
    end
  end

  test "show links to the app definition" do
    with_stubbed_adapter(entry: entry(definition_url: "https://example.test/dcomms-apps/peertube")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select "a[href='https://example.test/dcomms-apps/peertube']"
    end
  end

  test "outbound links open safely" do
    # These point at third-party sites; without noopener the opened page gets a handle on
    # this one via window.opener.
    with_stubbed_adapter(entry: entry(upstream_url: "https://joinpeertube.org")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select "a[href='https://joinpeertube.org'][rel~='noopener']"
    end
  end

  test "the about card is not double-wrapped" do
    # v.card already supplies .card-body > .card-text; adding another .card-body nests two
    # and visibly mis-pads the content.
    with_stubbed_adapter(entry: entry(long_description: "Real prose.")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select ".card-text .card-body", count: 0
    end
  end

  test "show says the upstream URL is missing rather than rendering an empty cell" do
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "body", text: /Not provided/
    end
  end

  #
  # show: releases
  #

  test "show lists every release with its version" do
    with_stubbed_adapter(entry: entry(releases: [ release(version: "2.0.0"), release(version: "1.0.0") ])) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "body", text: /2\.0\.0/
      assert_select "body", text: /1\.0\.0/
    end
  end

  test "show dates each release" do
    with_stubbed_adapter(entry: entry(releases: [ release(version: "2.0.0", released_at: "2026-03-04T10:00:00Z") ])) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "body", text: /Mar +4 2026/
    end
  end

  test "the newest release is marked latest" do
    with_stubbed_adapter(entry: entry(releases: [ release(version: "2.0.0"), release(version: "1.0.0") ])) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select "body", text: /Latest/
      assert_select ".badge", text: /Latest/, count: 1
    end
  end

  test "a release with no date says so rather than rendering blank" do
    with_stubbed_adapter(entry: entry(releases: [ release(version: "2.0.0") ])) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "body", text: /Date unknown/
    end
  end

  test "an entry with no releases explains itself" do
    with_stubbed_adapter(entry: entry(releases: [])) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "body", text: /No releases have been published/
    end
  end

  #
  # show: failures
  #

  test "show renders a banner rather than raising when the backend is unreachable" do
    with_stubbed_adapter(entry_raises: DcommsClient::ConnectionError.new("no route to host")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_response :success
      assert_select "div.alert-danger"
      assert_select "body", text: /no route to host/
    end
  end

  test "show renders a banner for an unknown entry rather than a blank page" do
    with_stubbed_adapter(entry_raises: DcommsClient::ServerError.new(code: -32000, message: "unknown catalog entry: nope")) do
      login_as(@user)
      get catalog_path("nope")

      assert_response :success
      assert_select "div.alert-danger"
      assert_select "body", text: /unknown catalog entry/
    end
  end

  test "show renders no content section when it has no entry" do
    # With nothing to describe, the detail cards must not render at all. An empty "About"
    # card would read as "this app has no metadata" instead of "the lookup failed".
    with_stubbed_adapter(entry_raises: DcommsClient::ConnectionError.new("down")) do
      login_as(@user)
      get catalog_path("peertube")

      assert_select ".card", count: 0
    end
  end

  test "the show route resolves" do
    assert_equal "/catalog/peertube", Rails.application.routes.url_helpers.catalog_path("peertube")
    assert_routing({ method: "get", path: "/catalog/peertube" },
                   { controller: "catalog", action: "show", id: "peertube" })
  end

  test "the index links each card to its show page" do
    with_stubbed_adapter(entries: [ entry(id: "peertube") ]) do
      login_as(@user)
      get catalog_index_path

      assert_select "a[href='/catalog/peertube']"
    end
  end
end
