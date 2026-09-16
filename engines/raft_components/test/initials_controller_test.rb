require_relative "test_helper"

class InitialsControllerTest < ActionDispatch::IntegrationTest
  def test_returns_svg_for_a_name
    get "/initials/Alice"
    assert_response :success
    assert_includes response.body, "<svg"
    assert_includes response.body, "AL"
  end

  def test_returns_svg_for_multi_word_name
    get "/initials/John%20Doe"
    assert_response :success
    assert_includes response.body, "JD"
  end

  def test_returns_svg_with_custom_size
    get "/initials/Alice", params: { size: 64 }
    assert_response :success
    assert_includes response.body, "width='64'"
  end

  def test_handles_empty_name
    get "/initials/%20"
    assert_response :success
    assert_includes response.body, "?"
  end

  def test_returns_svg_content_type
    get "/initials/Test"
    assert_response :success
    assert_includes response.content_type, "image/svg+xml"
  end

  def test_defaults_to_32px
    get "/initials/Test"
    assert_response :success
    assert_includes response.body, "width='32'"
  end
end
