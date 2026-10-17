require_relative "../test_helper"

#
# Integration tests for the read-only host-log view backed by VictoriaLogs. The
# service is stubbed so these run without a live VictoriaLogs instance.
#
class LogsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "logs-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Replace the controller's VictoriaLogs service with a stub that returns the given
  # records (or raises, to exercise the unreachable path).
  def with_stubbed_service(records: [], raises: nil, recorded: nil)
    fake = Object.new
    fake.define_singleton_method(:query_lines) do |query = "", **kwargs|
      recorded&.replace([ query, kwargs ])
      raise raises if raises
      records
    end

    LogsController.define_method(:service) { fake }
    yield
  ensure
    LogsController.send(:remove_method, :service)
  end

  def sample_records
    [
      { "_time" => "2026-09-08T00:59:12Z", "_stream" => "{host=\"tern\",programname=\"sshd\"}", "host" => "tern", "programname" => "sshd", "unit" => "ssh.service", "severity" => "info", "_msg" => "Accepted publickey for admin" },
      { "_time" => "2026-09-08T00:59:13Z", "_stream" => "{host=\"tern\",programname=\"cron\"}", "host" => "tern", "programname" => "cron", "unit" => "cron.service", "severity" => "info", "_msg" => "session opened" }
    ]
  end

  def test_index_requires_admin
    get logs_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  test "index_renders_records" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    assert_select "td", text: /sshd/
    # The message is the disclosure's summary, so it is still readable without expanding.
    assert_select "details summary", text: /Accepted publickey/
    assert_select "details summary", text: /session opened/
    # the time-range selector reflects the default window
    assert_select "button", text: /#{I18n.t("logs.index.range.#{Logs::Helper::DEFAULT_RANGE}")}/
  end

  test "the message body renders _msg separately, above the metadata list" do
    # `_msg` is the line the row exists to show, so it is not one labelled entry among many:
    # it gets its own unlabelled element, and the remaining fields follow in the record's own
    # order.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    message = JSON.parse(response.body)["rows"].first["cells"].find { |c| c["kind"] == "message" }

    assert_equal "Accepted publickey for admin", message["message"],
                 "the cell carries the full message on its own"
    refute_includes message["fields"].map { |f| f["key"] }, "_msg",
                    "_msg must not be repeated in the metadata list"
    assert_equal %w[_time _stream host programname unit severity],
                 message["fields"].map { |f| f["key"] }
  end

  test "the message cell discloses the full record when clicked" do
    # The JSON used to be its own column, which cost width on every row for a control most
    # rows never used. It now rides inside the message cell, so expanding a message shows the
    # record it came from and nothing is lost.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    body = response.body[%r{<details[^>]*>\s*<summary[^>]*>.*?</details>}m]

    refute_nil body, "the message must be a details disclosure"
    # The summary text sits in its own span so the stylesheet can hide just the text while
    # the disclosure is open, keeping the summary element as the collapse target.
    assert_match(/<summary[^>]*>\s*<span class="log-message-summary-text">\s*Accepted publickey for admin\s*<\/span>/, body)
    # The message itself, unlabelled, at the table's normal size (no `small`).
    assert_match(/<div class="mb-3"[^>]*>\s*Accepted publickey for admin\s*<\/div>/, body)
    assert_includes body, "<ul", "the metadata follows as an unstyled list"
    assert_includes body, "list-unstyled"
    assert_includes body, "<i>programname</i>", "keys are italic"
    assert_includes body, "sshd", "the body carries the record's values"
    refute_includes body, "<i>_msg</i>", "the message is not repeated as a labelled field"
  end

  test "the collapsed summary marks its text so it can be hidden when open" do
    # The expanded body repeats the message in full, so the summary text is hidden while the
    # disclosure is open -- otherwise the same line prints twice, once clipped and once whole.
    # That is a CSS rule keyed on `[open]`, so the span is what the stylesheet targets and
    # this test is what keeps the two ends from drifting apart.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "summary span.log-message-summary-text", minimum: 1
  end

  test "the expanded message is collapsed by clicking the body" do
    # Native `<details>` only toggles from its <summary>, and the summary's text is hidden while
    # open -- leaving an empty strip as the only pointer target, which is invisible and
    # undiscoverable. The body therefore carries a click action that closes the disclosure, so
    # clicking the text you are reading puts the row back.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "details.log-message[open]", false, "rows start collapsed"
    assert_select "details.log-message div[data-action*='collapseMessage']", minimum: 1
    assert_select "details.log-message ul[data-action*='collapseMessage']", minimum: 1
    # The summary is left intact as the control keyboard and assistive tech drive.
    assert_select "details.log-message summary", minimum: 1
    assert_select "details.log-message summary span.log-message-summary-text", minimum: 1
  end

  ##
  ## severity filter
  ##

  test "the severity filter offers every term the catalog defines" do
    # The picker's options come from the catalog, which is also what expands a term into the
    # levels it covers, so the menu and the query builder cannot disagree about what a term
    # means.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "a[href*='severity=']" do |links|
      terms = links.map { |l| l["href"][/severity=([a-z]+)/, 1] }.compact.uniq
      assert_equal Logs::FieldCatalog::SEVERITY_FILTER_TERMS.sort, terms.sort
    end
  end

  test "the severity filter does not offer individual critical levels" do
    # `crit` is a group covering crit/alert/emerg, so offering the members separately would
    # ask the user to choose between options they have no basis to distinguish.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    %w[emerg alert].each do |level|
      assert_select "a[href*='severity=#{level}']", false,
                    "#{level} is covered by the crit group and must not be offered"
    end
    # The group term itself is offered.
    assert_select "a[href*='severity=crit']"
  end

  test "the severity filter label shows the active level" do
    # A filtered view that reads like an unfiltered one is how someone concludes "there are no
    # errors" when they have simply filtered them out, so the button states the active level.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get "#{logs_path}?severity=err"
    end

    assert_select "button", text: /#{I18n.t("logs.index.severity.err")}/
  end

  test "the unfiltered severity label says so" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "button", text: /#{I18n.t("logs.index.severity.all")}/
  end

  test "an unknown severity param is dropped rather than echoed" do
    # The param is attacker-controllable via the query string. It is validated against the
    # level list, so an unrecognized value falls back to the unfiltered state instead of
    # reaching LogsQL or being reflected back into the label.
    recorded = []

    with_stubbed_service(records: sample_records, recorded: recorded) do
      login_as(@user)
      get "#{logs_path}?severity=not-a-level"
    end

    assert_select "button", text: /#{I18n.t("logs.index.severity.all")}/, count: 1
    assert_not_includes recorded.first.to_s, "not-a-level"
  end

  test "selecting a severity filters the query and keeps the other filters" do
    recorded = []

    with_stubbed_service(records: sample_records, recorded: recorded) do
      login_as(@user)
      get "#{logs_path}?range=6h&host=tern&severity=err"
    end

    query = recorded.first.to_s
    assert_includes query, 'severity:"err"'
    assert_includes query, 'host:"tern"'
    assert_includes query, "_time:6h"
  end

  test "crit expands to a union of the critical levels" do
    # The point of the group: `crit` is "crit or worse", so the query must find records stored
    # as alert and emerg too. LogsQL has no "or worse" operator, so the union is spelled out.
    recorded = []

    with_stubbed_service(records: sample_records, recorded: recorded) do
      login_as(@user)
      get "#{logs_path}?severity=crit"
    end

    query = recorded.first.to_s
    assert_includes query, 'severity:"crit"'
    assert_includes query, 'severity:"alert"'
    assert_includes query, 'severity:"emerg"'
    assert_includes query, " OR ", "the members must be ORed, not ANDed"
    assert_match(/\(.*\bOR\b.*\)/, query, "the OR must be grouped so it cannot bind loose")
  end

  test "a single-level term is not wrapped in a group" do
    # Parentheses are only needed where an OR would bind against the neighbouring AND terms.
    recorded = []

    with_stubbed_service(records: sample_records, recorded: recorded) do
      login_as(@user)
      get "#{logs_path}?severity=warning"
    end

    assert_not_includes recorded.first.to_s, "OR"
  end

  test "the clear filter link drops the severity" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get "#{logs_path}?severity=err"
    end

    assert_select "a", text: I18n.t("logs.index.clear_filters") do |links|
      assert_equal logs_path, links.first["href"]
    end
  end

  test "there is no separate details column" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    headers = response.body[/<thead.*?<\/thead>/m].scan(/<th\b.*?<\/th>/m)
    labels = headers.map { |h| h.gsub(/<[^>]+>/, "").strip }

    assert_equal Logs::FieldCatalog::HOST_FIELDS.size, headers.size,
                 "only catalog columns remain"
    refute_includes labels, "Details"
    refute_includes labels, "JSON"
  end

  test "index rows carry the dedupe key" do
    # The refresh controller seeds its "already shown" set from these attributes. Without
    # them it would re-append every row currently on the page on the first poll.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "tr[data-row-key]", count: 2
  end

  test "the refresh target is the tbody, not the table" do
    # Rows are inserted with `tbody.prepend(row)`. If the target were the <table>, the row
    # would land before the header row and the browser would hoist it out of the table --
    # new log lines would appear above the table instead of in it.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "tbody[data-logs-explorer-target='rows']"
    assert_select "table[data-logs-explorer-target]", count: 0
  end

  test "initial rows render inside the tbody" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "tbody[data-logs-explorer-target='rows'] tr[data-row-key]", count: 2
  end

  test "server-rendered rows have one cell per declared column" do
    # The row partial and the JSON endpoint must emit the same cells, or a live row would
    # have a different number of columns than a loaded one.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    header_cells = response.body[/<thead.*?<\/thead>/m].scan(/<th\b/).size
    first_row = response.body[/<tbody.*?<\/tbody>/m][/<tr\b.*?<\/tr>/m]

    assert_equal header_cells, first_row.scan(/<td\b/).size,
                 "a row must have a cell for every header column"
    assert_equal Logs::FieldCatalog::HOST_FIELDS.size, header_cells
  end

  test "the severity column leads the table and has no heading text" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    headers = response.body[/<thead.*?<\/thead>/m].scan(/<th\b.*?<\/th>/m)

    assert_includes headers.first, "log-severity-cell", "the stripe column comes first"
    assert_equal "", headers.first.gsub(/<[^>]+>/, "").strip, "it carries no label"
    # The other columns still have their headings.
    assert_equal "Time", headers[1].gsub(/<[^>]+>/, "").strip
  end

  test "the severity cell is a coloured stripe, not text" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    cell = response.body[/<tbody.*?<\/tbody>/m][/<td\b[^>]*log-severity-cell.*?<\/td>/m]

    # The colour is a class on the <td> itself. A nested element would sit inside the cell's
    # padding, so the stripe would not fill the cell.
    assert_match(/<td\b[^>]*class="[^"]*\btext-bg-success\b[^"]*"/, cell)
    assert_includes cell, "log-severity-cell"
    # The level is still discoverable even though it is not visible text.
    assert_includes cell, 'title="info"'
    refute_includes cell, ">info<", "the level must not be rendered as visible text"
  end

  test "the severity stripe has no inner coloured element" do
    # Guards the specific regression: the colour used to sit on a span inside the cell, which
    # the cell padding then inset.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    cell = response.body[/<tbody.*?<\/tbody>/m][/<td\b[^>]*log-severity-cell.*?<\/td>/m]
    inner = cell.sub(/\A<td\b[^>]*>/, "").sub(/<\/td>\z/, "")

    refute_match(/text-bg-/, inner, "no inner element may carry the colour")
  end

  test "the html row and the json row describe the same cells" do
    # This is the pairing that keeps live rows looking like loaded ones: `logs/_row` and
    # `log_row_cells` must agree, since the client rebuilds the JSON shape as markup.
    json_cells = nil
    html_cell_count = nil

    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
      html_cell_count = response.body[/<tbody.*?<\/tbody>/m][/<tr\b.*?<\/tr>/m].scan(/<td\b/).size

      get data_logs_path
    end
    json_cells = JSON.parse(response.body)["rows"].first["cells"]

    assert_equal html_cell_count, json_cells.size
  end

  test "each json row publishes the same cell classes the html row renders" do
    #
    # The regression this pins: the severity stripe was styled by a class the row template
    # composed in Ruby, while the Stimulus controller composed its own class strings in JS.
    # The two lists were written out independently, drifted, and appended rows lost the
    # stripe's width (the server-rendered cell carried the column's `fit`, the JS cell did
    # not). Publishing the classes with each row means there is one derivation, and this test
    # is what fails if a second one is ever introduced.
    #
    html_classes = nil
    json_rows = nil

    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
      first_row = response.body[/<tbody.*?<\/tbody>/m][/<tr\b.*?<\/tr>/m]
      html_classes = first_row.scan(/<td\b[^>]*\bclass="([^"]*)"/).flatten

      get data_logs_path
    end
    json_rows = JSON.parse(response.body)["rows"]

    assert_equal html_classes.size, json_rows.first["classes"].size,
                 "the JSON row must publish one class string per cell"
    assert_equal html_classes, json_rows.first["classes"]

    # And the classes must survive a record with no severity, so the neutral stripe is not a
    # special case the client has to know about.
    blank = json_rows.first["classes"].first
    assert_includes blank, "text-bg-success", "info severity maps to success"
    assert_includes blank, "log-severity-cell"
  end

  test "an unknown severity still renders a neutral stripe of the same width" do
    # The stripe carries meaning in its width even when the level is unknown, so a missing
    # level must not collapse the cell or drop the width class.
    record = sample_records.first.merge("severity" => nil)
    classes = nil

    with_stubbed_service(records: [ record ]) do
      login_as(@user)
      get data_logs_path
    end
    classes = JSON.parse(response.body)["rows"].first["classes"]

    assert_includes classes.first, "log-severity-cell"
    assert_includes classes.first, "text-bg-secondary"
  end

  ##
  ## pause / resume control
  ##

  test "the pause control starts with pause visible and resume hidden" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "button[data-logs-explorer-target='pauseButton']" do |buttons|
      refute_includes buttons.first["class"].to_s.split, "d-none",
                      "pause must be visible while polling"
    end
    assert_select "button[data-logs-explorer-target='resumeButton'].d-none"
  end

  test "pause and resume are hidden with the d-none class, not an inline style" do
    # The controller toggles `classList` (`d-none`). Its counterpart on the server must use
    # the SAME mechanism: an inline `display: none` cannot be cleared by removing a class,
    # so the Resume button would never reappear and the pause button would simply vanish.
    # A class is the mechanism CSS and JS can both drive. `hide: true` emits it.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "button[data-logs-explorer-target='resumeButton'].d-none"
    assert_select "button[data-logs-explorer-target='resumeButton']" do |buttons|
      refute_includes buttons.first["style"].to_s, "display:",
                      "hiding must not rely on an inline display style"
    end
  end

  test "the disconnected badge starts hidden the same way" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "[data-logs-explorer-target='status'].d-none"
  end

  test "server-rendered row keys match the json endpoint" do
    # The two must agree on identity, or a polled row would duplicate one already on the
    # page.
    keys_from_html = []
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
      keys_from_html = response.body.scan(/data-row-key="([^"]*)"/).flatten.map { |k| CGI.unescapeHTML(k) }

      get data_logs_path
    end

    keys_from_json = JSON.parse(response.body)["rows"].map { |r| r["key"] }
    assert_equal keys_from_html.sort, keys_from_json.sort
  end

  def test_index_requests_the_configured_default_limit_and_default_range
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get logs_path
    end

    query, kwargs = recorded
    # Default range is the last hour, expressed as a LogsQL `_time:` filter.
    assert_equal "_time:#{Logs::Helper::DEFAULT_RANGE}", query
    assert_equal Conf.logs_default_limit, kwargs[:limit]
  end

  def test_index_applies_the_selected_range
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get logs_path(range: "24h")
    end

    assert_equal "_time:24h", recorded.first
  end

  def test_index_ignores_an_unknown_range_value
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get logs_path(range: "99y")
    end

    assert_equal "_time:#{Logs::Helper::DEFAULT_RANGE}", recorded.first
  end

  def test_index_renders_empty_state_when_there_are_no_logs
    with_stubbed_service(records: []) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    # The empty state is an alert, not a table row: with no rows there is no table at all,
    # and the wording must not imply the filters caused the emptiness.
    assert_select ".alert-info", text: /No logs have been received/
  end

  def test_index_distinguishes_no_matches_from_no_logs
    # "nothing matched your filters" and "there are no logs" call for different next
    # actions, so the empty state must not conflate them.
    #
    # NOTE: the filter goes in an explicit query string. `logs_path(host: "tern")` silently
    # returns a bare `/logs`, because route helpers drop params that are not route segments.
    with_stubbed_service(records: []) do
      login_as(@user)
      get "#{logs_path}?host=tern"
    end

    assert_response :success
    assert_select ".alert-info", text: /No logs matched these filters/
    assert_no_match(/No logs have been received/, response.body)
  end

  def test_index_renders_warning_banner_when_victorialogs_is_unreachable
    with_stubbed_service(raises: VictoriaLogs::RequestError.new("VictoriaLogs request failed: 500")) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    assert_select ".alert-danger"
    assert_select ".alert-danger", text: /VictoriaLogs/
  end

  def test_index_does_not_500_on_connection_failure
    with_stubbed_service(raises: Faraday::ConnectionFailed.new("connection refused")) do
      login_as(@user)
      get logs_path
    end

    assert_response :success
    assert_select ".alert-danger"
  end

  #
  # data (JSON refresh, Step 4)
  #

  def test_data_requires_admin
    get data_logs_path
    assert_response :redirect
    assert_redirected_to login_path
  end

  test "data_returns_json_rows_with_the_display_fields_preformatted" do
    # The client renders rows from these cells rather than re-deriving them, so a live row
    # is formatted by the same Ruby that formatted the initial page.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["rows"].size

    row = body["rows"].first
    assert row["key"].present?, "a row key is required for client-side dedupe"
    assert row["cells"].any?, "a row must carry its cells"
    assert_equal Logs::FieldCatalog::HOST_FIELDS.size, row["cells"].size,
                 "one cell per catalog column"
    # The message cell carries the record so the disclosure works without a second request.
    message = row["cells"].find { |c| c["kind"] == "message" }
    assert message.present?, "the message cell is present"
    assert message["message"].present?, "the message cell carries the full message"
    keys = message["fields"].map { |f| f["key"] }
    assert_includes keys, "programname", "the body carries the record field by field"
    refute_includes keys, "_msg", "_msg is rendered on its own, not as a labelled field"
  end

  test "data row cells cover every catalog column" do
    # Regression: the client used to hardcode three columns, so live rows silently dropped
    # the ones it did not know about. The cell count is what keeps the two in step.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    cells = JSON.parse(response.body)["rows"].first["cells"]
    values = cells.map { |c| c["value"] }

    # sample_records[0] carries a severity. The source cell carries its two parts instead of
    # a `value`, so it is asserted through those.
    assert_includes values, "info"
    assert_equal "host", cells[2]["value"], "the context column"
    assert_equal "sshd", cells[3]["value"], "the source column"
    assert_equal Logs::FieldCatalog::HOST_FIELDS.size, cells.size
  end

  test "data row cells are in catalog order" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    cells = JSON.parse(response.body)["rows"].first["cells"]

    # severity, _time, context, source, _msg. The message is its own disclosure kind because it
    # carries the record, not just a string. Context and source are distinct kinds because they
    # are styled differently -- the context is the low-variance half. `priority` and `host` are
    # not columns -- see the catalog for why.
    assert_equal %w[severity time context source message], cells.map { |c| c["kind"] }
  end

  test "the context and source columns read dc_app for a container record" do
    # The context is what KIND of thing logged this. For a container that is the app
    # installation, not the machine and not the binary inside the container.
    container_record = {
      "_time" => "2026-09-08T00:59:13Z", "_stream_id" => "c1", "host" => "tern",
      "container_name" => "dawa-web-1", "dc_app" => "peertube",
      "severity" => "info", "_msg" => "container line"
    }
    cells = nil

    with_stubbed_service(records: [ container_record ]) do
      login_as(@user)
      get data_logs_path
      cells = JSON.parse(response.body)["rows"].first["cells"]
    end

    assert_equal "context", cells[2]["kind"]
    assert_equal "peertube", cells[2]["value"]
    assert_equal "source", cells[3]["kind"]
    assert_equal "dawa-web-1", cells[3]["value"]
  end

  test "the context and source columns read host and the daemon for a host record" do
    cells = nil

    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
      cells = JSON.parse(response.body)["rows"].first["cells"]
    end

    assert_equal "host", cells[2]["value"]
    assert_equal "sshd", cells[3]["value"]
  end

  test "the severity cell leads the row and carries a colour" do
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    cell = JSON.parse(response.body)["rows"].first["cells"].first

    assert_equal "severity", cell["kind"]
    # sample_records severity is "info".
    assert_equal "success", cell["color"]
  end

  test "an absent severity still renders a stripe" do
    # The column's width carries meaning, so a missing level must not collapse the cell.
    records = [ { "_time" => "2026-09-08T00:59:12Z", "_stream_id" => "s1", "_msg" => "no level" } ]

    with_stubbed_service(records: records) do
      login_as(@user)
      get data_logs_path
    end

    cell = JSON.parse(response.body)["rows"].first["cells"].first

    assert_equal "severity", cell["kind"]
    assert_nil cell["color"], "an unknown level must fall back to neutral, not invent one"
  end

  test "unit is not a column" do
    # `unit` is carried by records but is deliberately not a display column; it should not
    # appear as a cell, though the record's other fields still appear in the message body.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    cells = JSON.parse(response.body)["rows"].first["cells"]

    refute_includes cells.map { |c| c["value"] }, "ssh.service"
    refute_includes Logs::FieldCatalog::HOST_FIELDS, :unit
  end

  test "an empty column renders a placeholder cell rather than being omitted" do
    # A column is always rendered, even when the record has no value for it. Dropping the
    # cell instead would shift every following column, so a row with a missing field would
    # stop lining up with its header.
    #
    # `_time` is the remaining column that a record can genuinely omit (the others are
    # derived: severity falls back to neutral, source always resolves a context).
    record = sample_records.first.merge("_time" => nil)

    with_stubbed_service(records: [ record ]) do
      login_as(@user)
      get data_logs_path
    end

    cells = JSON.parse(response.body)["rows"].first["cells"]
    time_cell = cells[1]

    assert_equal :none, time_cell["kind"].to_sym
    assert_equal I18n.t("logs.index.none"), time_cell["value"]
    assert_equal Logs::FieldCatalog::HOST_FIELDS.size, cells.size,
                 "the placeholder must not change the cell count"
  end

  def test_data_row_keys_are_stable_and_content_derived
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
      first = JSON.parse(response.body)["rows"].map { |r| r["key"] }

      get data_logs_path
      second = JSON.parse(response.body)["rows"].map { |r| r["key"] }

      assert_equal first, second, "keys must not change between polls"
      assert_equal first.uniq, first, "keys must be distinct within a batch"
    end
  end

  def test_data_keys_distinguish_records_sharing_a_timestamp
    # Several logs can share a `_time` (syslog bursts, journald). Keying on time alone
    # would make the client discard real rows as duplicates.
    records = [
      { "_time" => "2026-09-08T00:59:12Z", "_stream_id" => "s1", "_msg" => "first" },
      { "_time" => "2026-09-08T00:59:12Z", "_stream_id" => "s1", "_msg" => "second" }
    ]

    with_stubbed_service(records: records) do
      login_as(@user)
      get data_logs_path
    end

    keys = JSON.parse(response.body)["rows"].map { |r| r["key"] }
    assert_equal 2, keys.uniq.size
  end

  def test_data_returns_the_newest_time_as_the_next_cursor
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get data_logs_path
    end

    cursor = JSON.parse(response.body)["cursor"]
    assert_equal Time.zone.parse("2026-09-08T00:59:13Z").utc.iso8601(6), cursor
  end

  def test_data_polls_only_newer_logs_when_given_a_cursor
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?cursor=2026-09-08T00:59:13.000000Z"
    end

    query, = recorded
    # Half-open on the left: the browser already holds the row at exactly the cursor, so
    # including it would re-send that row on every poll.
    assert_equal "_time:(2026-09-08T00:59:13.000000Z, now]", query
  end

  def test_data_replaces_the_range_with_the_cursor_window
    # The cursor is the more specific bound, so the window is not also applied.
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?range=24h&cursor=2026-09-08T00:59:13.000000Z"
    end

    query, = recorded
    assert_includes query, "_time:("
    refute_includes query, "_time:24h"
  end

  def test_data_ignores_a_malformed_cursor_and_falls_back_to_the_window
    # The cursor is echoed back by the client, so it is untrusted. A junk value must not
    # reach LogsQL.
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?range=6h&cursor=not-a-timestamp"
    end

    assert_equal "_time:6h", recorded.first
  end

  def test_data_ignores_a_cursor_in_the_future
    # Clock skew (or a hand-edited value) could put the cursor ahead of the server, making
    # the interval empty-to-invalid. Falling back to the window shows something instead.
    recorded = []
    future = (Time.now.utc + 1.day).iso8601(6)

    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?range=1h&cursor=#{ERB::Util.url_encode(future)}"
    end

    assert_equal "_time:1h", recorded.first
  end

  def test_data_applies_filters_to_the_query
    recorded = []
    with_stubbed_service(records: [], recorded: recorded) do
      login_as(@user)
      get "#{data_logs_path}?host=tern&programname=sshd&text=failed"
    end

    query, = recorded
    assert_includes query, 'host:"tern"'
    assert_includes query, 'programname:"sshd"'
    assert_includes query, '"failed"'
  end

  def test_data_reports_a_backend_failure_as_an_error_not_an_empty_batch
    # If a refresh failure returned `rows: []`, an outage would be indistinguishable from
    # a quiet log -- the one thing a sysadmin most needs to notice.
    with_stubbed_service(raises: VictoriaLogs::RequestError.new("VictoriaLogs request failed: 500")) do
      login_as(@user)
      get data_logs_path
    end

    assert_response :bad_gateway
    body = JSON.parse(response.body)
    assert_equal [], body["rows"]
    assert_match(/VictoriaLogs/, body["error"])
  end

  def test_data_returns_an_empty_batch_when_there_are_no_new_logs
    with_stubbed_service(records: []) do
      login_as(@user)
      get "#{data_logs_path}?cursor=2026-09-08T00:59:13.000000Z"
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["rows"]
    assert_equal 0, body["count"]
    assert_nil body["error"]
  end

  def test_index_seeds_the_cursor_from_the_newest_rendered_row
    # Without this the first poll would refetch the whole window.
    with_stubbed_service(records: sample_records) do
      login_as(@user)
      get logs_path
    end

    assert_select "[data-logs-explorer-cursor-value='#{Time.zone.parse("2026-09-08T00:59:13Z").utc.iso8601(6)}']"
  end
end
