module Metrics::FilterHelper

  def time_window_buttons(url_opts:)
    tag.div(class: "btn-group") do
      safe_join([
        v.link_button(
          label: t("nav.day"),
          url: url_for(window: "day", **url_opts),
          fill: params[:window] == "day",
          turbo: true
        ),
        v.link_button(
          label: t("nav.week"),
          url: url_for(window: "week", **url_opts),
          fill: params[:window] == "week",
          turbo: true
        ),
        v.link_button(
          label: t("nav.month"),
          url: url_for(window: "month", **url_opts),
          fill: params[:window] == "month",
          turbo: true
        ),
        v.link_button(
          label: t("nav.quarter"),
          url: url_for(window: "quarter", **url_opts),
          fill: params[:window] == "quarter",
          turbo: true
        )
      ])
    end
  end
end
