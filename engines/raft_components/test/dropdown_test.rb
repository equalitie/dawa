require_relative "test_helper"

class DropdownTest < ActionView::TestCase

  def test_dropdown
    expected = %[
      <div class="dropdown">
        <button name="button" type="button" class=" btn btn-outline-dark dropdown-toggle" style="" aria-expanded="false" data-bs-toggle="dropdown" data-bs-popper-config="{&quot;strategy&quot;:&quot;fixed&quot;}">Button</button>
        <ul class="dropdown-menu">
          <li>
            <button name="button" type="button" class="dropdown-item btn btn-outline-dark" style="">hello</button>
          </li>
        </ul>
      </div>
    ].gsub(/\n\s*/, "")

    output = v.dropdown_button do |menu|
      menu.item { v.button("hello") }
    end
    assert_equal expected, output
  end
end
