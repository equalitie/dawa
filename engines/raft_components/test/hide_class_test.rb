require_relative "test_helper"

#
# Tests for how components hide themselves.
#
# The mechanism matters because it is shared across the Ruby/JS boundary. Hiding uses the
# `d-none` class: a class is the one mechanism CSS and JS can both drive, so a stylesheet
# can target it for state-driven rules and a script toggles it with `classList`. An inline
# `display: none` looks identical in a screenshot but cannot be cleared by removing a class,
# which is how a pause button once vanished without its resume counterpart appearing.
#
class HideClassTest < ActionView::TestCase
  def test_hide_option_emits_the_d_none_class
    html = v.button(label: "Resume", hide: true)

    assert_includes html, "d-none"
  end

  def test_hide_option_does_not_emit_an_inline_display_style
    # The regression guard: an inline `display: none` would not be cleared by removing the
    # class, so the element could never be shown again.
    html = v.button(label: "Resume", hide: true)

    refute_includes html, "display: none"
    refute_includes html, "display:none"
  end

  def test_hide_false_emits_no_d_none_class
    html = v.button(label: "Pause", hide: false)

    refute_includes html, "d-none"
  end

  def test_hiding_merges_with_caller_classes
    # `hide:` must add to the class list, not replace it.
    html = v.button(label: "X", hide: true, class: "btn-white")

    assert_includes html, "d-none"
    assert_includes html, "btn-white"
  end

  def test_hide_does_not_disturb_an_explicit_style
    html = v.button(label: "X", hide: true, style: "padding: 4px 8px")

    assert_includes html, "padding: 4px 8px"
    assert_includes html, "d-none"
  end

  def test_a_plain_component_honours_the_hide_option
    # BoxComponent applies @html[:class], so `hide:` works through the common args.
    html = v.box(icon: "house", hide: true) do
      "content"
    end

    assert_includes html, "d-none"
  end

  def test_the_spin_swap_is_css_driven_and_still_uses_the_class
    # The spinner swap is a CSS state selector (`button[disabled] .when-disabled`), which is
    # why hiding is a class rather than an attribute only JS could change.
    html = v.button(label: "Save", icon: "save", spin: true)

    assert_includes html, "when-disabled"
  end
end
