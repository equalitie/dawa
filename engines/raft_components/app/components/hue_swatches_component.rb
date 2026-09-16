#
# = v.hue_swatches("user[hue]")
#  do |swatches|
#  - hue_steps do |hue|
#    - swatches.with_color(h: hue, s: 70, l: 70, value: hue)

class HueSwatchesComponent < SwatchesComponent
  include RaftComponents::ColorHelper

  def initialize(*args, **kwargs)
    super(*args, **kwargs)
  end

  def call
    hue_choices.each do |hue|
      with_color(h: hue, s: 70, l: 70, value: hue)
    end
    super
  end
end
