module SidebarHelper

  def sidebar_items
    sb = {}
    sb[:home] = {
      label: t("sidebar.home"),
      icon: "house-door-fill",
      path: main_app.home_path,
      active: active?(c: "home")
    }
    # sb[:search] = {
    #   label: t("sidebar.search"),
    #   icon: "search",
    #   path: "#", #main_app.search_path,
    #   active: active?(c: "search")
    # }
    sb[:users] = {
      label: t("sidebar.users"),
      icon: "people-fill",
      path: main_app.users_path,
      active: active?(c: "users")
    }
    sb[:apps] = {
      label: t("sidebar.apps"),
      icon: "boxes",
      path: main_app.apps_path,
      active: active?(c: "apps")
    }
    sb[:containers] = {
      label: t("sidebar.containers"),
      icon: "hdd-rack",
      path: main_app.containers_path,
      active: active?(c: "containers")
    }
    sb[:logs] = {
      label: t("sidebar.logs"),
      icon: "list-columns-reverse",
      path: main_app.logs_path,
      active: active?(c: "logs")
    }
    sb[:metrics] = {
      label: t("sidebar.metrics"),
      icon: "speedometer",
      path: main_app.metrics_path,
      active: active?(c: "metrics")
    }
    sb[:backups] = {
      label: t("sidebar.backups"),
      icon: "cloud-arrow-up",
      path: main_app.backups_path,
      active: active?(c: "backups")
    }
    sb[:troubleshoot] = {
      label: t("sidebar.troubleshoot"),
      icon: "life-preserver",
      path: main_app.troubleshoot_path,
      active: active?(c: "troubleshoot")
    }
    sb[:settings] = {
      label: t("sidebar.settings"),
      icon: "gear-fill",
      path: main_app.settings_path,
      active: active?(c: "settings")
    }
    sb[:auth] = {
      label: t("sidebar.authentication"),
      icon: "patch-check",
      path: auth.credentials_path,
      active: active?(c: "auth/credentials")
    }
    sb
  end

end
