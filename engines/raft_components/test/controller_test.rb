require_relative "test_helper"

class ControllerTest < ActionView::TestCase
  def test_controller_with_string_value
    html = v.controller("test", name: "hello")
    assert_includes html, "data-controller='test'"
    assert_includes html, "data-test-name-value='hello'"
  end

  def test_controller_with_numeric_value
    html = v.controller("test", count: 42)
    assert_includes html, "data-test-count-value='42'"
  end

  def test_controller_with_boolean_value
    html = v.controller("test", enabled: true)
    assert_includes html, "data-test-enabled-value='true'"
  end

  def test_controller_with_array_value
    html = v.controller("test", tags: ["a", "b", "c"])
    assert_includes html, "data-test-tags-value="
    # Array values must be JSON-encoded for Stimulus
    assert_includes html, '["a","b","c"]'
  end

  def test_controller_with_hash_value
    config = { "document" => { "fileType" => "docx", "title" => "Test" }, "editorConfig" => { "mode" => "edit" } }
    html = v.controller("onlyoffice", config: config)
    assert_includes html, "data-onlyoffice-config-value="
    # Hash values must be JSON-encoded for Stimulus
    assert_includes html, '{"document"'
    assert_includes html, '"fileType":"docx"'
    assert_includes html, '"editorConfig":{"mode":"edit"}'
  end

  def test_controller_with_symbol_key_hash_value
    config = { title: "Event", all_day: true, start_time: "2026-01-01" }
    html = v.controller("test", config: config)
    assert_includes html, "data-test-config-value="
    assert_includes html, '"title":"Event"'
    assert_includes html, '"all_day":true'
    assert_includes html, '"start_time":"2026-01-01"'
  end

  def test_controller_with_nested_hash_value
    config = { levels: { deep: { value: 1 } } }
    html = v.controller("test", config: config)
    assert_includes html, "data-test-config-value="
    assert_includes html, '"levels":{"deep":{"value":1}}'
  end

  def test_controller_with_empty_hash_value
    html = v.controller("test", config: {})
    assert_includes html, "data-test-config-value='{}'"
  end
end
