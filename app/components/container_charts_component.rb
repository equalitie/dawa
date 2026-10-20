#
# like ChartsComponent, but use the container-stats stimulus
# controller.
#
class ContainerChartsComponent < ChartsComponent
  private
  def stimulus_controller_name
    "container-stats"
  end
end
