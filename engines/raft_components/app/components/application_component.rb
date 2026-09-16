class ApplicationComponent < ViewComponent::Base
  include RaftComponents::ViewHelper
  include RaftComponents::ColorHelper
  include RaftComponents::IconHelper

  attr_accessor :parent

  # if set to true, this component can only be created
  # via a form builder, e.g. `form.v.component_name()`
  class_attribute :requires_builder, default: false

  attr_accessor :factory


  # this are the keyword args the the abstract super class ApplicationComponent
  # handles. some sublclasses may wish to operate on all keyword args that are
  # not in this list.
  COMMON_ARGS = [ :html, :name, :disabled, :class, :style, :factory, :data, :params, :id, :hide, :tooltip ]

  #
  # common arguments for all components:
  #
  # - :id      -- the element's dom id.
  # - :html    -- set html element attributes directly.
  #               e.g. html: {style: "width: 100%"}
  # - :class   -- alias for `html: {class: x }`
  # - :disable -- this component is disabled if true
  # - :data    -- used to build "data-*" element attributes.
  # - :params  -- additional params included in any request made by this component
  # - :name    -- name attribute for input elements
  # - :hide    -- if set to true, "display: none" is added to the style
  # - :tooltip -- tooltip text for this component.
  #
  def initialize(**args)
    @name ||= args[:name]
    @id   ||= args[:id]
    @disabled = args[:disabled]

    @html = HashWithIndifferentAccess.new(args[:html])
    if @id
      @html[:id] = @id
    end
    @html[:disabled] ||= @disabled
    if args[:class]
      @html[:class] = [args.delete(:class), @html[:class]].compact.join(" ")
    end
    @html[:class] ||= ""
    if args[:style]
      @html[:style] = [args.delete(:style), @html[:style]].compact.join(" ")
    end
    @html[:style] ||= ""
    if args[:hide]
      @html[:style] += ";display: none;"
    end

    @factory = args[:factory]
    if self.class.requires_builder
      return ArgumentError, "Form builder is required" unless @factory&.builder
    end
    @data = HashWithIndifferentAccess.new(args[:data])
    @params = HashWithIndifferentAccess.new(args[:params])
    if args[:tooltip].present?
      @data["bs-toggle"] = "tooltip"
      @data["bs-title"] = args[:tooltip]
    end
  end

  def without_common(args_hash)
    args_hash.except(*COMMON_ARGS)
  end

  def with_common(args_hash)
    args_hash.slice(*COMMON_ARGS)
  end

  def render_haml(haml, locals = {})
    Haml::Template.new { haml.strip_heredoc }.render(self, locals).html_safe
  end

  #
  # see https://github.com/ViewComponent/view_component/blob/main/lib/view_component/slotable.rb#L380
  # Keep track of which slots are set up with eager_slot.
  class_attribute :eager_slots, default: [].to_set

  #
  # Mark a slot as eager, meaning its block will be evaluated immediately
  # when the slot is set (via with_SLOT_NAME) rather than lazily when the
  # slot is rendered. This is important when the slot block depends on
  # thread-global state such as Raft::Encryption.workspace_key.
  #
  #   class MyRow < ApplicationComponent
  #     renders_many :cells, "CellComponent"
  #     eager_slot :cells
  #   end
  #
  def self.eager_slot(slot_name)
    self.eager_slots = eager_slots.dup.add(slot_name.to_sym)
  end

  #
  # Override __vc_set_slot in order to:
  #   1. Set the child component's parent attribute (if defined).
  #   2. Eagerly capture the block if the slot is marked as eager.
  #
  # By default, slots don't have access to their parent component. I find that
  # there are many situations where I want access to the parent. So, we manually
  # set the parent here.
  #
  # This is brittle and might break because it taps into the ViewComponent internals.
  #
  def __vc_set_slot(slot_name, slot_definition = nil, *args, **kwargs, &block)
    if block && self.class.eager_slots.include?(slot_name)
      content = view_context.capture(&block)
      block = proc { content }
    end
    slot = super
    if slot&.instance_variable_get("@__vc_component_instance")&.respond_to?(:parent=)
      slot.instance_variable_get("@__vc_component_instance").parent = self
    end
  end

  #
  # Override `before_render` to evaluate the content block eagerly if the
  # class has `eager_content` set. By default ViewComponent evaluates the
  # block lazily during rendering, but some components need the block to
  # run first to set up state (e.g. column definitions).
  #
  def before_render
    if self.class.has_eager_content? && !@__vc_content_evaluated
      content
    end
    super
  end

  #
  # Declare that this component's content block should be evaluated eagerly
  # (before the template renders) rather than lazily during template rendering.
  #
  def self.eager_content
    self.has_eager_content = true
  end

  class_attribute :has_eager_content, default: false

  #
  # The form builder is set if component is called from a form
  # e.g form_with(...) {|form| form.v.button(...) }
  #
  def builder
    @factory&.builder
  end

  def v
    @factory
  end

  protected

  #
  # Adds a parameter to an already static string URL
  #
  def add_params(url, params = {})
    if params.present?
      uri = URI(url)
      params    = Hash[URI.decode_www_form(uri.query || '')].merge(params)
      uri.query = URI.encode_www_form(params)
      uri.to_s
    else
      url
    end
  end

  #
  # Extracts parameters from a URL string
  #
  def extract_params(url)
    uri = URI(url)
    return {} if uri.query.blank?
    URI.decode_www_form(uri.query).to_h
  end

  def remove_params(url)
    uri = URI(url)
    uri.query = nil
    uri.to_s
  end

  def field_name
    if @name
      if builder
        if @name =~ /(.*)\[(.*)\]/
          "%s[%s][%s]" % [ builder.object_name, $1, $2 ]
        else
          "%s[%s]" % [ builder.object_name, @name ]
        end
      else
        @name
      end
    else
      builder&.object_name
    end
  end

  #
  # returns the current value bound to the component.
  #
  # if there is a builder, then we use the builder's
  # record and access it's `name` field
  #
  def field_value
    if builder && @name
      index = nil
      if @name.count("[") != 0
        name, index = @name.split(/[\[\]]/)
      else
        name = @name
      end
      if builder&.object&.respond_to?(name)
        if index
          builder.object.send(name).send("[]", index).to_s
        else
          builder.object.send(name).to_s
        end
      end
    elsif @value
      @value.to_s
    end
  end

end
