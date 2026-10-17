module Logs::ButtonsHelper
  # Severity filter. Selecting a term is a full page navigation like every other control,
  # so the active state lives in the URL and the refresh endpoint sees it without any JS.
  # The label shows the selected term so the current filter is readable without opening the
  # menu, and the icon takes the term's colour so the button itself signals urgency.
  #
  # The terms come from the catalog, where `crit` is a group covering crit/alert/emerg
  # ("crit or worse"). The grouping lives there rather than in the menu so the picker and
  # the query builder cannot disagree about what a term means.
  #
  # `nil` means "no severity filter", which is why the blank option is explicit: dropping
  # the param is a different request from filtering on an empty value.

  def log_filter_severity_dropdown
    attrs = {
      label: severity_filter_label,
      icon: "exclamation-triangle",
      color: severity_filter_color,
      fill: (true unless @filters.severity.nil?)
    }
    v.dropdown_button(**attrs) do |menu|
      menu.item do
        v.link_button(
          label: t("logs.index.severity.all"),
          url: logs_path_with({ severity: nil }),
          icon: "slash-circle",
          # class: ("active" unless @filters.severity.present?)
        )
      end
      Logs::FieldCatalog::SEVERITY_FILTER_TERMS.each do |term|
        menu.item do
          v.link_button(
            label: t("logs.index.severity.#{term}"),
            url: logs_path_with({ severity: term }),
            # class: ("active" if @filters.severity == term),
            # `text-bg-hover` opts the item into the lighter `:hover` variant, since a
            # coloured menu item would otherwise give no feedback that it is clickable.
            class: "text-bg-#{severity_filter_color(term)} text-bg-hover",
          )
        end
      end
    end
  end

  #
  # The severity picker's button label.
  #
  # Shows the active term rather than a static "Severity" so the current filter is readable
  # without opening the menu -- a filtered log view that looks identical to an unfiltered one
  # is how someone concludes "there are no errors" when they simply filtered them out.
  #
  # The value is validated against the filter terms by `LogsFilters`, so an unrecognized param
  # falls back to the unfiltered label rather than echoing attacker-controlled text.
  #
  def severity_filter_label
    if Logs::FieldCatalog::SEVERITY_FILTER_TERMS.include?(current_filters.severity)
      t("logs.index.severity.#{current_filters.severity}")
    else
      t("logs.index.severity.all")
    end
  end

  #
  # The severity picker's button colour, or nil when unfiltered.
  #
  # A group term (`crit`) is coloured by the WORST level it covers, so "crit or worse" reads
  # as the emergency it is rather than being left neutral. An unfiltered picker has no colour
  # to signal, so it keeps the default.
  #
  def severity_filter_color(level = nil)
    level ||= current_filters.severity
    levels = Logs::FieldCatalog.severity_levels_for(level)
    return nil if levels.empty?

    Logs::FieldCatalog.severity_color(levels.first)
  end


end
