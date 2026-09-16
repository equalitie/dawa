module LayoutHelper

  #
  # let views modify <body data-*="">
  #
  # e.g. `data_body.add controller: "scroll"`
  # => <body data-controller="scroll">
  #
  def body_data
    @body_data ||= DataHash.new
  end

  private

  class DataHash < HashWithIndifferentAccess
    def add(hsh)
      hsh.each do |k,v|
        self[k] ||= []
        self[k] << v
      end
    end
    def to_h()
      super {|k,v|
        ["data-#{k}", v.join(" ")]
      }
    end
  end
  private_constant :DataHash

end
