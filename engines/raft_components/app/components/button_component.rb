#
# Abstract superclass of all the components that create things that *look* like
# buttons (regardless if it is a button or not)
#
# It is not functional on its own, but can be used to create quick visual mockups
#
# # Arguments
#
# * `display`:
#   * button: renders the button like a button
#   * link: renders the button using spacing like a button, but without the border or fill
#   * text: renders the button as if it was inline text
# * `form_data`: hash of html data attributes for the form
#
# # Hidden Forms
#
# Most ButtonComponent subclasses build hidden forms for the necessary
# button parameters (when self.class.hidden_form is true).
#
# When hidden_form is true and there is no builder context, then the hidden
# form is put inline.
#
# When hidden_form is true and there is a form builder, then the hidden form is
# added to content_for(:hidden_content). This is because we cannot put the
# hidden form inline, because it is illegal in HTML to nest forms, and the
# browser will just ignore the nested form tags.
#
# This behavior can be manually overridden with button arguments:
# `hidden_form_inline: true` or `hidden_form_inline: false`.
#
# For this to work with turbo-frame and turbo-stream responses, the view must
# manually render `content_for(:hidden_content)`.
#
class ButtonComponent < ApplicationComponent
  class_attribute :default_color, default: "dark"
  class_attribute :default_icon, default: nil
  class_attribute :default_label, default: nil
  class_attribute :default_method, default: :put
  class_attribute :button_type, default: :button
  class_attribute :hidden_form, default: false

  def initialize(\
      value = nil, url: nil, action: nil, method: nil, \
      label: nil, icon: nil, spin: nil, image: nil, fill: false, border: true, size: nil, color: nil, \
      form_data: nil, form: nil, hidden_form_inline: nil, override: nil, display: "button", **args)
    super(**args)
    @label    = value || label
    @icon     = icon || self.class.default_icon
    @size     = size
    @spin     = spin
    @image    = image
    @url      = url
    @action   = action
    @method   = method || self.class.default_method
    @form_data = form_data
    @hidden_form_inline = hidden_form_inline

    @html.merge!(
      type: self.class.button_type,
      class: resolve_css_class(
        existing: @html[:class],
        color: color,
        display: display,
        size: size,
        border: border,
        fill: fill
      )
    )
    if override
      @html.merge! override
    end
    if form
      @html[:form] = form
    end
  end

  def call
    case form_disposition
    when :hidden_content
      helpers.content_for :hidden_content do
        hidden_form
      end
      button_tag
    when :inline
      safe_join([ hidden_form, button_tag ])
    when :none
      button_tag
    end
  end

  protected

  def button_tag
    options = @html.merge(data: @data, id: @id)
    if @name
      options[:name] = @name
    elsif @params.present? && @params.count == 1 && (@hidden_form_inline != true && !self.class.hidden_form)
      # if there is no hidden form, we can encode a single param key=value
      # with a button using name=value
      options[:name], options[:value] = @params.first
    end
    helpers.button_tag(inner_content, options)
  end

  def link_tag
    options = @html.merge(data: @data)
    if @disabled
      options[:class] = [ "disabled", options[:class] ].join(" ")
    end
    if @params
      @url = add_params(@url, @params)
    end
    helpers.link_to(inner_content, @url, options)
  end

  def inner_content
    if @label.nil? && self.class.default_label
      @label = t(self.class.default_label)
    end
    if @image
      helpers.image_tag(@image) + helpers.content_tag(:label, @label)
    elsif content? && @icon == self.class.default_icon && @label == self.class.default_label
      content
    elsif @icon
      if @spin
        # when this button is disabled the spinner is shown instead of the icon.
        safe_join([
          content_tag("alt-span", class: "when-disabled", style: "display:none") {
            icon(icon: "spinner", label: @label, size: icon_size)
          },
          content_tag("alt-span", class: "when-enabled") {
            icon(icon: @icon, label: @label, size: icon_size)
          }
        ])
      else
        icon(icon: @icon, label: @label, size: icon_size)
      end
    elsif @label
      @label
    else
      content
    end
  end

  # returns the string for the hidden form
  def hidden_form
    unless @disabled
      @html[:form] ||= "hidden_form_#{rand(1_000_000_000)}"
      helpers.form_with(url: @url, method: @method, id: @html[:form], data: @form_data, html: { style: "display:none" }) do |form|
        safe_join([ content, form_hidden_field_tags ])
      end
    end
  end

  def form_hidden_field_tags
    if @data["turbo-frame"]
      # I am not sure if it is by design or a bug or I am doing something wrong,
      # but when there are nested turbo frames then setting data-turbo-frame does
      # not produce the correct turbo-frame header in the request (it always uses the
      # outermost frame id).
      #
      # to work around this, whenever a button has data-turbo-frame set we
      # additionally add turbo_frame to the params so we don't have to rely
      # on the turbo-frame header.
      @params[:turbo_frame] = @data["turbo-frame"]
    end

    if @params&.any?
      safe_join(build_hidden_fields(@params))
    end
  end

  def build_hidden_fields(obj, prefix = nil)
    case obj
    when Hash
      obj.flat_map do |key, value|
        new_prefix = prefix ? "#{prefix}[#{key}]" : key.to_s
        build_hidden_fields(value, new_prefix)
      end
    when Array
      obj.flat_map do |value|
        build_hidden_fields(value, "#{prefix}[]")
      end
    else
      [ helpers.hidden_field_tag(prefix, obj, id: nil) ]
    end
  end

  #
  # should there be a hidden form, and if so where?
  #
  # putting the form in hidden content is usually a bad idea, because
  # it doesn't work with turbo streams or other methods of partially updating
  # the page.
  #
  # todo: remove using hidden content for forms, instead, put inline after the
  # form if a builder is active?
  #
  def form_disposition
    if @html[:form]
      # already specified a form, do don't render another one
      :none
    elsif @hidden_form_inline === false
      # honor explicit override
      :hidden_content
    elsif self.class.hidden_form
      if builder
        # in a form context, can't put inline
        :hidden_content
      else
        # no form, ok to put inline
        :inline
      end
    else
      # default to no form
      :none
    end
  end

  def resolve_css_class(existing:, color:, display:, size:, border:, fill:)
    classes = [ existing ]
    color ||= self.class.default_color
    if display == "button"
      classes << "btn"
      if size
        classes << "btn-#{size}"
      end
      if border && fill
        classes << "btn-#{color}"
      elsif border && !fill
        classes << "btn-outline-#{color}"
      else
        classes << "link-#{color}"
      end
    elsif display == "link"
      classes << "btn btn-link btn-#{size} link-#{color}"
    elsif display == "text"
      classes << "btn-text link-#{color}"
    end
    classes.join(" ")
  end

  def icon_size
    case @size
    when "lg"
      "2em"
    else
      "1em"
    end
  end
end
