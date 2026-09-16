class RoleBadgeComponent < StateBadgeComponent
  self.field = :role
  self.map = {
    "admin" => [ "dark", "role.admin" ],
    "user" => nil
  }
end
