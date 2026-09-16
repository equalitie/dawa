module LocalizationHelper
  #
  # local keys are cool (e.g. `t(".title")`)
  # but they don't have any fallback that traverses the
  # localization tree to find a matching key.
  #
  # this tt() helper (translate traversal?) will
  # try first a scope based on just the controller and
  # then try a scope based on controller + action.
  #
  # for example, in the things_controller/index.html:
  #
  # t(".title") => t("things.index.title")
  # tt(".title) => t("things.title") or t("things.index.title")
  #
  def tt(key, **options)
    key = key.to_s
    key = key.sub(/\A\./, "")                      # normalize: ".title" -> "title"
    default_base = @virtual_path.tr("/", ".")      # e.g. things.index (already ends with action or partial name)
    higher_base = default_base.split(".")[0..-2].join(".")   # e.g. things
    try_first = "#{higher_base}.#{key}"            # e.g. things.title
    fall_back = [
      I18n.t("#{default_base}.#{key}", **options), # e.g. things.index.title
      I18n::MissingTranslation
    ]
    I18n.t(try_first, default: fall_back, **options)
  end
end
