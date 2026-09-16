require_relative "test_helper"

class InitialAvatarTest < ActiveSupport::TestCase
  def test_creates_svg_with_defaults
    avatar = RaftComponents::InitialAvatar.new("John Doe")
    svg = avatar.to_s
    assert_includes svg, "<svg"
    assert_includes svg, "xmlns='http://www.w3.org/2000/svg'"
    assert_includes svg, "width='32'"
    assert_includes svg, "height='32'"
  end

  def test_uses_custom_size
    avatar = RaftComponents::InitialAvatar.new("Alice", size: 64)
    svg = avatar.to_s
    assert_includes svg, "width='64'"
    assert_includes svg, "height='64'"
  end

  def test_initials_from_first_name
    avatar = RaftComponents::InitialAvatar.new("john")
    assert_equal "JO", avatar.initials
  end

  def test_initials_from_two_names
    avatar = RaftComponents::InitialAvatar.new("john doe")
    assert_equal "JD", avatar.initials
  end

  def test_initials_from_many_names
    avatar = RaftComponents::InitialAvatar.new("one two three four")
    assert_equal "OT", avatar.initials
  end

  def test_initials_from_underscore_name
    avatar = RaftComponents::InitialAvatar.new("john_doe")
    assert_equal "JD", avatar.initials
  end

  def test_initials_from_single_underscore_name
    avatar = RaftComponents::InitialAvatar.new("john_doe")
    assert_equal "JD", avatar.initials
  end

  def test_initials_in_text_tag
    avatar = RaftComponents::InitialAvatar.new("Alice")
    svg = avatar.to_s
    assert_includes svg, ">AL<"
  end

  def test_empty_name_uses_question_mark
    avatar = RaftComponents::InitialAvatar.new("")
    assert_equal "?", avatar.name
    assert_includes avatar.to_s, ">?<"
  end

  def test_whitespace_name_uses_question_mark
    avatar = RaftComponents::InitialAvatar.new("   ")
    assert_equal "?", avatar.name
  end

  def test_default_shape_is_circle
    avatar = RaftComponents::InitialAvatar.new("Test")
    assert_includes avatar.to_s, "<circle"
    assert_not_includes avatar.to_s, "<rect"
  end

  def test_rect_shape
    avatar = RaftComponents::InitialAvatar.new("Test", shape: :rect)
    assert_includes avatar.to_s, "<rect"
  end

  def test_hue_sets_fill_color
    avatar = RaftComponents::InitialAvatar.new("Test", hue: 180)
    assert_includes avatar.fill, "hsl(180"
  end

  def test_fill_is_deterministic
    a1 = RaftComponents::InitialAvatar.new("SomeName")
    a2 = RaftComponents::InitialAvatar.new("SomeName")
    assert_equal a1.fill, a2.fill
  end

  def test_different_names_have_different_fills
    a1 = RaftComponents::InitialAvatar.new("Alice")
    a2 = RaftComponents::InitialAvatar.new("Bob")
    assert_not_equal a1.fill, a2.fill
  end

  def test_font_size_decreases_with_more_initials
    single = RaftComponents::InitialAvatar.new("A")
    double = RaftComponents::InitialAvatar.new("A B")
    assert_operator single.font_size, :>, double.font_size
  end

  def test_white_text_on_dark_background
    avatar = RaftComponents::InitialAvatar.new("Test")
    svg = avatar.to_s
    assert_includes svg, "fill='white'"
    assert_includes svg, "fill-opacity='0.75'"
  end
end
