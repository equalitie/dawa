module CatalogHelper
  #
  # Render a URL as an outbound link, or a muted "not provided" when absent.
  #
  # Every detail URL on the catalog show page is optional: the backend does not send them
  # yet. An empty cell would read as a rendering bug, so say explicitly that the value is
  # missing.
  #
  def external_link_or_blank(url)
    return content_tag(:span, t("apps.not_provided"), class: "text-muted") if url.blank?

    # noopener/noreferrer: these point at third-party sites, so the opened page must not
    # get a handle on this one via window.opener.
    link_to(url, url, target: "_blank", rel: "noopener noreferrer")
  end

  # Placeholder prose for an entry with no long description yet.
  def long_description_placeholder
    CatalogPlaceholderText.paragraphs(@entry.id)
  end
end
