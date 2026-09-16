#
# Usage:
#
#     = v.paginate(options) do
#       ...
#
# Options:
#
#   :turbo -- if true, use turbo frame for pagination (default: true)
#

class PaginateComponent < ApplicationComponent
  # include Pagy::Method

  haml_template <<~HAML
    - if pagy && show_pagination?
      - if @turbo
        %turbo-frame(id="turbo-paginate" target="_top" data-turbo-action="advance")
          - if @top
            = pagination_widget
          - if content?
            = content
            - if @bottom
              .mt-3= pagination_widget
      - else
        - if @top
          = pagination_widget
        - if content?
          = content
          - if @bottom
            .mt-3= pagination_widget
    - else
      = content
  HAML

  def initialize(turbo: true, top: true, bottom: true, html: {}, **args)
    super(**args)
    @turbo = turbo
    @top = top
    @bottom = bottom
    @html = html
  end

  def pagination_widget
    @widget ||= begin
      pagy_widget = if pagy.send(:keyset?)
        pagy.next_tag(self.method(:next_tag)).html_safe
      elsif pagy.send(:offset?)
        pagy.series_nav(:bootstrap, **link_options).html_safe
      elsif pagy.send(:countless?)
        pagy.previous_tag.html_safe +
        pagy.next_tag.html_safe
      end
      if @html.any?
        content_tag(:div, pagy_widget, **@html)
      else
        pagy_widget
      end
    end
  end

  def next_tag(next_param, text, aria_label: nil)
    # NOTE: building your own URL is dangerous.
    # we use Rack::Utils.build_query to escape bad parameters
    url = helpers.request.path + "?" + Rack::Utils.build_query(helpers.request.query_parameters.merge(page: next_param))
    link_to(
      icon(label: "Next", icon: "caret-right-fill"),
      url,
      class: "btn btn-outline-secondary",
      data: { "turbo-frame": "turbo-paginate" }
    )
  end

  def pagy
    @pagy ||= helpers.instance_variable_get("@pagy")
    # @pagy ||= if @relation
    #  options = Pagy.options.merge({ limit: 10 })
    #  pagy = Pagy::OffsetPaginator.paginate(view_context, @relation, **options).first
    #  helpers.instance_variable_set("@pagy", pagy)
    #  pagy
    # end
  end

  #
  # not sure why .keyset? and .offset? are protected
  #
  def show_pagination?
    (pagy&.send(:keyset?) && pagy.next) ||
    (pagy&.send(:offset?) && pagy.count > pagy.limit) ||
    (pagy&.send(:countless?) && pagy.next)
  end

  #
  # the new version of pagy has done away with :anchor_string
  # option. Until this is added back, there is no clean way to
  # modify the attributes of the anchor tag. Instead, we do
  # something super hacky: modify the URL by adding a "fragment"
  # to the end that closes the href="" with a quote and then
  # inserts its own text into the anchor element tag.
  #
  # we basically do an injection attack on the pagy link helper.
  #
  def link_options
    if @turbo
      { fragment: %(" data-turbo-frame="turbo-paginate") }
    else
      {}
    end
  end
end
