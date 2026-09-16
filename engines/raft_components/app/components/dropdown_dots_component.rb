class DropdownDotsComponent < DropdownButtonComponent
  def initialize(*args, **kwargs)
    super(*args, icon: "three-dots", border: false, size: "sm", triangle: false, **kwargs)
  end
end
