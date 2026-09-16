module InviteHelper

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

end
