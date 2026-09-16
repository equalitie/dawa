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
      path: "#", #main_app.workspaces_path,
      active: active?(c: "users")
    }
    sb[:apps] = {
      label: t("sidebar.apps"),
      icon: "boxes",
      path: "#", #main_app.workspace_files_path(@workspace),
      active: active?(c: "apps")
    }
    sb[:logs] = {
      label: t("sidebar.logs"),
      icon: "list-columns-reverse",
      path: "#", # main_app.workspace_events_path(@workspace),
      active: active?(c: "logs")
    }
    sb[:metrics] = {
      label: t("sidebar.metrics"),
      icon: "speedometer",
      path: "#", #main_app.profiles_path,
      active: active?(c: "metrics")
    }
    sb[:troubleshoot] = {
      label: t("sidebar.troubleshoot"),
      icon: "life-preserver",
      path: "#", #main_app.profiles_path,
      active: active?(c: "troubleshoot")
    }
    sb[:settings] = {
      label: t("sidebar.settings"),
      icon: "gear-fill",
      path: "#", #auth.credentials_path,
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
