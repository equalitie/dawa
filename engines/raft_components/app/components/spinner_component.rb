#
# display a spinner
#
class SpinnerComponent < ApplicationComponent
  #
  # size: sm, md
  #
  def initialize(label: nil, size: "md", **kwargs)
    super(**kwargs)
    @size = size.to_s
    @label = label
  end

  def call
    icon("spinner", @label, size: @size)
  end
end
