module BreadcrumbHelper
  def active_navigation_item
    @active_navigation_item ||= sidebar_items&.values&.detect { |v| v.is_a?(Hash) && v[:active] }
  end

  def breadcrumbs(**kwargs, &block)
    auto = kwargs.fetch(:auto, true)
    kwargs.delete(:auto)
    content_for(:breadcrumbs) do
      v.breadcrumbs(**kwargs) do |bc|
        bc.with_home(main_app.home_path)
        if auto && active_navigation_item
          bc.with_crumb {
            link_to(
              active_navigation_item[:label],
              active_navigation_item[:path]
            )
          }
        end
        if block
          yield bc
        end
      end
    end
  end

end
