module RoleHelper

  def invite_role_options_for_select(include_none: false)
    array = [
      [t("role.user"), "user"],
      [t("role.admin"), "admin"]
    ]
    if include_none
      array << [t("role.none"), "none"]
    end
    array
  end

  def display_role(role)
    role = role.to_s
    case role
    when "admin" then t("role.admin")
    when "user" then t("role.user")
    else t("role.none")
    end
  end

  def choose_role(user)
    v.dropdown_button(label: display_role(user.role)) do |menu|
      menu.item { v.update_button(
        icon: "gear",
        label: display_role("admin"),
        url: user_path(user.id),
        params: { user: { role: "admin" } }
      )}
      menu.item { v.update_button(
        icon: "person",
        label: display_role("user"),
        url: user_path(user.id),
        params: { user: { role: "edit" } }
      )}
    end
  end

  def display_active(is_active)
    if is_active
      t("user.active")
    else
      t("user.inactive")
    end
  end

  def choose_active(user)
    color = user.is_active? ? "success" : "dark"
    v.dropdown_button(label: display_active(user.is_active?), fill: true, color: color) do |menu|
      menu.item { v.update_button(
        icon: "check",
        label: display_active(true),
        url: user_path(user.id),
        params: { user: { is_active: "true" } }
      )}
      menu.item { v.update_button(
        icon: "x",
        label: display_active(false),
        url: user_path(user.id),
        params: { user: { is_active: "false" } }
      )}
    end
  end

end
