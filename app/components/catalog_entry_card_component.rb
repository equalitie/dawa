#
# One catalog entry rendered as a bootstrap card.
#
#   = v.catalog_entry_card(entry)
#
# The catalog is what CAN be installed, so the card is informational only: there is no
# install action here. Installing creates an app, which is a separate concern.
#
# Fields the backend does not send yet (`description`, `updated_at`) render as
# placeholders. That is deliberate: the card is built against the intended shape of
# `apps/list`, and placeholder text is honest about the gap where inventing a value
# would not be. See docs/dcommsctl-api-requests.md.
#
class CatalogEntryCardComponent < ApplicationComponent
  haml_template <<~HAML
    = v.box(icon: @icon, size: "lg", class: "h-100") do |box|
      .d-flex.justify-content-between.align-items-baseline.gap-2
        .fw-semibold.text-truncate= @entry.name
        %code.small.text-muted.text-nowrap= @entry.id
      .mb-3{data: {placeholder: placeholder_description? ? "true" : nil}}
        - if placeholder_description?
          %em.text-muted= description
        - else
          = description
      - box.with_footer do
        .d-flex.justify-content-between.small.text-muted
          %span.text-nowrap= version_label
          - if @entry.updated?
            %span.text-nowrap= updated_label
  HAML

  #
  # Placeholder icon. A real per-entry icon needs a field on the catalog entry (or an
  # asset shipped with the app definition); until then every card shows the same generic
  # glyph rather than a misleading app-specific one.
  #
  PLACEHOLDER_ICON = "box-seam"

  def initialize(entry, **args)
    super(**args)
    @entry = entry
    @icon = PLACEHOLDER_ICON
  end

  # Body text. The backend sends no description yet, so this is generated filler, shown
  # in italics and flagged with a data attribute so it is never mistaken for real data.
  def description
    return @entry.description if @entry.described?

    CatalogPlaceholderText.tagline(@entry.id)
  end

  def placeholder_description? = !@entry.described?

  def version_label
    return t("apps.version_number", version: @entry.version) if @entry.versioned?

    t("apps.version_unknown")
  end

  def updated_label
    t("apps.catalog_updated", date: helpers.format_date(@entry.updated_at, :date))
  end
end
