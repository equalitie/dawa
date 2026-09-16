require_relative "../test_helper"

class CopyComponentTest < ActionView::TestCase
  def test_input_is_readonly
    html = v.copy(text: "copy me")
    assert_includes html, 'type="text"'
    # Haml renders boolean attributes without a value (just "readonly").
    assert_includes html, " readonly"
    assert_includes html, 'value="copy me"'
  end

  def test_disabled_renders_plain_text
    html = v.copy(text: "copy me", disabled: true)
    assert_includes html, "copy me"
    assert_not_includes html, "input"
  end
end
