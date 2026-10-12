module AppsHelper
  def link_to_app_domain(app)
    if app.domain.present?
      link_to app.domain, [Conf.public_protocol, "://", app.domain].join, target: "_new"
    else
      t("apps.domain_unknown")
    end
  end
end
