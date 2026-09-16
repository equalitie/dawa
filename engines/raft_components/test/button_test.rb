require_relative "test_helper"

class ButtonTest < ActionView::TestCase

  OUTPUTS ||= {
    %(<button name="button" type="button" class=" btn btn-outline-dark" style="">Mr Button</button>) =>
      -> { v.button(label: "Mr Button") }
  }
  def test_simple_button
    OUTPUTS.each do |output, proc|
      assert_equal output, instance_exec(&proc)
    end
  end
end
