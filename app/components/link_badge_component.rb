class LinkBadgeComponent < StateBadgeComponent
  self.field = :state
  self.map = {
    "expired" => [ "dark", "link.state.expired" ],
    "pending" => [ "primary", "link.state.pending" ],
    "used" => [ "danger", "link.state.used" ]
  }
end
