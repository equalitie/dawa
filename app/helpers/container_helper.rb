module ContainerHelper
  COLUMNS = [
    [:shrink, "Status"],
    [:grow, "Name"],
    [:shrink, "ID"],
    [:grow, "Image"],
    [:shrink, :hide_md, "Created"],
    [:shrink, :hide_md, "Changed"]
  ].freeze

  def container_columns
    COLUMNS
  end
end
