if !Rails.env.development?
  class DevController < ActionController::Base
  end
else
  class DevController < ActionController::Base
    layout :choose_layout

    before_action do
      theme.context_url = dev_path
      theme.header_icon_url = helpers.avatar_url(avatar)
    end

    def index
      theme.header_text = "Layout Development"
      theme.set_hue(80)
    end

    def components
      theme.header_text = "Component Gallery"
      theme.set_hue(230)
      @userspace = Userspace.order("RANDOM()").detect{|us| us.data["workspace_key"] }
      if @userspace
        Raft::Encryption.workspace_key = [@userspace.data["workspace_key"]].pack("H*")
        @profile = @userspace.user.profile
      end
    end

    def columns
      theme.header_text = "Column Test"
      theme.set_hue(160)
    end

    def images
      theme.header_text = "Image Display"
      theme.set_hue(300)
    end

    def layout
      theme.set_hue(rand(360))
      theme.header_text = "Layout Explorer"
      theme.show_sidebar = true
      theme.sidebar_items = sidebar_items
      @content = "".html_safe
      if params[:long_line].present?
        @content += "<p>#{'x'*300}</p>".html_safe
      end
      if params[:tall].present?
        @content += paragraph * 100
      else
        @content += paragraph
      end
      if params[:local_scroll].present?
        theme.local_scroll = true
      else
        theme.local_scroll = false
      end
      if params[:flash].present?
        flash.now[:danger] = "Pay attention!"
      end
      if params[:card].present?
        @content = render_to_string partial: "card"
      end
    end

    def button_action
      sleep 1
      head :ok
    end

    def autocomplete_list
      html = []
      200.times do |i|
        html << helpers.content_tag(:div, data: {value: i}, class: "autocomplete-choice") {
          helpers.content_tag(:span, Faker::Name.name)
        }
      end
      render html: helpers.safe_join(html), layout: false
    end

    def submit_form
      render plain: params.inspect
    end

    helper_method :toggle_button
    helper_method :params_hash
    helper_method :avatar

    private

    def choose_layout
      theme.header_status_partial = "dev/session"
      if params[:inset].present?
        "layout/inset"
      else
        "layout/application"
      end
    end

    def avatar
      @avatar ||= {"seed" => rand(1000000), "hue" => rand(100)}
    end

    def params_hash
      @params_hash ||= params.permit!.to_h.transform_values {|v| v.present? ? v : nil }
    end

    def toggle_button(param)
      if params_hash[param]
        helpers.v.link_button(
          data: {"turbo-prefetch" => "false" },
          label: param.to_s,
          url: dev_layout_path,
          icon: "check-square",
          params: params_hash.merge(param => nil)
        )
      else
        helpers.v.link_button(
          data: {"turbo-prefetch" => "false" },
          label: param.to_s,
          url: dev_layout_path,
          icon: "square",
          params: params_hash.merge(param => "y")
        )
      end
    end

    ICONS = %w(cake cassette cloud-rain dice-5 magic moon-stars radioactive snow speaker star terminal virus yin-yang usb-symbol umbrella truck server)
    def sidebar_items
      items = {
        home: {
          label: "Home",
          icon: "house-door-fill",
          path: "#",
          active: false
        },
        search: {
          label: "Search",
          icon: "search",
          path: "#",
          active: true
        },
        workspaces: {
          label: "Workspaces",
          icon: "building",
          path: "#",
          active: false
        }
      }
      if params[:sidebar_tall].present?
        30.times do |i|
          items[i] = {
            label: "item #{i}",
            icon: ICONS.sample,
            path: "#",
            active: false
          }
        end
      end
      items
    end

    def paragraph
      <<~TXT.html_safe
        <p>Feugiat est, sit amet vulputate elit. Aenean tristique mattis ipsum,
        imperdiet pellentesque ante elementum scelerisque. Donec porta rhoncus
        enim id elementum. Nullam vitae lectus sapien. Donec sed rutrum risus.
        Vestibulum ante ipsum primis in faucibus orci luctus et ultrices
        posuere cubilia curae; Vestibulum non tincidunt nisi. Ut sit amet
        molestie tortor. Nullam elementum laoreet pretium. Nam eget sem
        placerat libero convallis placerat a a lorem. Cras hendrerit
        tortor eu nulla aliquet suscipit. Phasellus finibus a tellus
        luctus pellentesque. Vivamus at neque tortor. Donec rutrum
        vitae turpis sit amet vulputate. Suspendisse mattis ante vitae
        ante blandit, in cursus dui fringilla. Quisque efficitur ac ipsum
        vitae maximus.</p>
      TXT
    end
  end
end
