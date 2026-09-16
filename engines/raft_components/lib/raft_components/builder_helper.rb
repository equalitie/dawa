module RaftComponents
  module BuilderHelper
    def v
      RaftComponents::ComponentFactory.new(@template, builder: self)
    end
  end
end
