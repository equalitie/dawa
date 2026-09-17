#
# One installed app rendered as a bootstrap card.
#
#   = v.app_card(app)
#
# An "app" here is an installed thing (a deployment with its own data), NOT a catalog
# entry. The catalog card, `CatalogEntryCardComponent`, is the sibling of this one: it
# describes what CAN be installed, this describes what IS.
#
# `inst/list` currently returns only instance NAMES (directory names), so in practice only
# `id` is populated and `version`/`domain`/`status` are all nil. Those render as explicit
# placeholders rather than blanks or invented values -- a blank cell is ambiguous (missing
# data? a bug? not applicable?) and an invented one is worse. See docs/dcommsctl-api-requests.md.
#
class AppCardComponent < ApplicationComponent
  haml_template <<~HAML
    = v.box(icon: @icon, size: "lg", class: "h-100") do |box|
      .d-flex.justify-content-between.align-items-baseline.gap-2
        .fw-semibold.text-truncate= @app.id
        - if @app.catalog_entry_id.present?
          %code.small.text-muted.text-nowrap= @app.catalog_entry_id
      .mb-2= v.app_status_badge(@app)
      %dl.row.small.mb-0
        %dt.col-4.text-muted= t("apps.version")
        %dd.col-8.mb-1
          - if @app.version.present?
            = @app.version
          - else
            %em.text-muted{data: {placeholder: "true"}}= t("apps.version_unknown")
        %dt.col-4.text-muted= t("apps.domain")
        %dd.col-8.mb-1
          - if @app.domain.present?
            = @app.domain
          - else
            %em.text-muted{data: {placeholder: "true"}}= t("apps.domain_unknown")
  HAML

  #
  # Placeholder icon, same reasoning as the catalog card: a real per-app icon needs an asset
  # or a catalog field, so every card shows the same generic glyph rather than a misleading
  # app-specific one.
  #
  PLACEHOLDER_ICON = "box-seam"

  def initialize(app, **args)
    super(**args)
    @app = app
    @icon = PLACEHOLDER_ICON
  end
end
