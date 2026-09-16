class ActiveBadgeComponent < StateBadgeComponent
  self.field = :is_active
  self.map = {
    true: ["primary", "user.active"],
    false: ["secondary", "user.inactive"]
  }
end
