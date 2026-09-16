require_relative "../test_helper"

# Define component classes outside the test class so ViewComponent
# can resolve slot references by class name.
class EagerItemComponent < ApplicationComponent
  haml_template <<~HAML
    .item= content
  HAML
end

class EagerListComponent < ApplicationComponent
  renders_many :items, "EagerItemComponent"
  eager_slot :items

  haml_template <<~HAML
    .list
      - items.each do |item|
        = item
  HAML
end

class SetupFirstComponent < ApplicationComponent
  eager_content
  attr_reader :items

  def initialize(*)
    @items = []
    super
  end

  def add_item(name)
    @items << name
  end

  haml_template <<~HAML
    %ul
      - items.each do |item|
        %li= item
  HAML
end

class CombinedComponent < ApplicationComponent
  eager_content
  renders_many :items, "EagerItemComponent"
  eager_slot :items

  attr_reader :headers

  def initialize(*)
    @headers = []
    super
  end

  def header(name)
    @headers << name
  end

  haml_template <<~HAML
    .combined
      .headers
        - headers.each do |h|
          %span.header= h
      .items
        - items.each do |item|
          = item
  HAML
end

class ApplicationComponentTest < ActionView::TestCase
  include RaftComponents::ViewHelper

  def vc
    @vc ||= ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil).tap do |ctx|
      ctx.extend(RaftComponents::ViewHelper)
    end
  end

  def render_inline(component, &block)
    vc.render(component, &block)
  end

  # ── eager_content ──────────────────────────────────────────────

  def test_eager_content_evaluates_block_before_template
    html = render_inline(SetupFirstComponent.new) do |c|
      c.add_item("alpha")
      c.add_item("beta")
    end
    assert_includes html, "<li>alpha</li>"
    assert_includes html, "<li>beta</li>"
  end

  def test_eager_content_block_runs
    html = render_inline(SetupFirstComponent.new) do |c|
      c.add_item("only")
    end
    assert_includes html, "<li>only</li>"
  end

  # ── eager_slot ──────────────────────────────────────────────

  def test_eager_slot_captures_block
    html = render_inline(EagerListComponent.new) do |c|
      c.with_item { "eager content" }
    end
    assert_includes html, "eager content"
  end

  def test_eager_slot_multiple_items
    html = render_inline(EagerListComponent.new) do |c|
      c.with_item { "first" }
      c.with_item { "second" }
    end
    assert_includes html, "first"
    assert_includes html, "second"
  end

  def test_eager_slot_with_content_method
    html = render_inline(EagerListComponent.new) do |c|
      c.with_item_content("direct content")
    end
    assert_includes html, "direct content"
  end

  # ── combined ──────────────────────────────────────────────

  def test_eager_content_and_eager_slot_together
    html = render_inline(CombinedComponent.new) do |c|
      c.header("Name")
      c.header("Value")
      c.with_item { "alpha" }
      c.with_item { "beta" }
    end
    assert_includes html, "Name"
    assert_includes html, "Value"
    assert_includes html, "alpha"
    assert_includes html, "beta"
  end

  def test_eager_content_state_available_to_eager_slots
    html = render_inline(CombinedComponent.new) do |c|
      c.header("Count")
      c.with_item { "(#{c.headers.size} header)" }
    end
    assert_includes html, "(1 header)"
  end

  # ── table_row id ──────────────────────────────────────────────

  def test_table_row_emits_id_attribute
    html = render_inline(TableRowComponent.new(id: "row-42")) do |r|
      r.with_cell { "cell content" }
    end
    assert_includes html, 'id="row-42"'
  end
end
