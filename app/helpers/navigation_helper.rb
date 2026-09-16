module NavigationHelper
  #
  # returns the string 'active' if all the arguments match the current params values.
  #
  # examples:
  #
  #   active(controller: 'passwords')
  #   active(controller: 'passwords', action: 'show')
  #
  # When using the hash form, :a is an alias for :action, and :c is an alias for :controller.
  #
  #    active(c: 'passwords')
  #
  # You can match using a regular expression:
  #
  #    active(a: /show|edit/)
  #
  # If the string ends in "/", it matches namespaced param values.
  # For example:
  #
  #   active(c: "users/")
  #
  # Will match controllers "users", "users/enroll", etc.
  #
  # You can also match OR conditions by specifying multiple hashes as the arguments:
  #
  #   active(c: "users", a: "show")      # matches controller "users" AND action "show"
  #   active({c: "users"}, {a: "show"})  # matches controller "users" OR action "show"
  #
  def active(*args)
    args.each do |hsh|
      is_active = hsh.keys.inject(true) { |memo, key|
        param_key = key
        param_key = :controller if param_key == :c
        param_key = :action     if param_key == :a
        param_key = :path       if param_key == :p
        if param_key == :path
          match_against = request.path
        else
          match_against = if defined?(navigation_as)
            navigation_as[param_key] || params[param_key]
          else
            params[param_key]
          end
        end
        memo &&= begin
          if hsh[key].is_a? Regexp
            !!(hsh[key] =~ match_against)
          elsif hsh[key].is_a?(String) && hsh[key].end_with?("/")
            if match_against.index("/")
              match_against.starts_with?(hsh[key])
            else
              match_against == hsh[key].chop
            end
          else
            [ hsh[key] ].flatten.include?(match_against)
          end
        end
      }
      if is_active
        return 'active'
      end
    end
    nil
  end

  def active?(...)
    !!active(...)
  end

  def nav_tab(label, path, klass, disabled: false)
    content_tag('li', class: 'nav-item') do
      link_to(label, path, class: [ 'nav-link', klass, disabled ? 'disabled' : nil ].compact.join(' '))
    end
  end

  def nav_link(active:, path:, label:, icon:, disabled: false)
    if disabled
      content_tag(:span, class: "nav-link disabled #{active}") do
        icon(icon, label)
      end
    else
      link_to(icon(icon, label), path, class: "nav-link #{active}")
    end
  end
end
