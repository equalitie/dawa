module AppsHelper

  # app might be nil of backend can't be reached or the app was deleted
  def link_to_app(app)
    link_to(
      app&.domain&.presence || params[:app_id],
      app_path(app&.id || params[:app_id])
    )
  end

  def link_to_app_jobs(app)
    link_to(
      t("jobs.title"),
      app_jobs_path((app&.id || params[:app_id]))
    )
  end

  def link_to_app_domain(app)
    if app.domain.present?
      link_to app.domain, [Conf.public_protocol, "://", app.domain].join, target: "_new"
    else
      t("apps.domain_unknown")
    end
  end
end
