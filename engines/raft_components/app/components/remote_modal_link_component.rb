class RemoteModalLinkComponent < LinkComponent
  def initialize(**args)
    super
    @data["turbo-frame"] = "modal-frame"
    @data["turbo-stream"] = "true"
  end
end
