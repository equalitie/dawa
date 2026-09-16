#
# display a profile or profile-like object:
#
# [      ]  Display Name
# [ icon ]  @username
# [      ]  [optional content]
#
# If the size is small and content is included, we omit the
# display name
#
# http://localhost:3000/components#profiles
#
#
class ProfileComponent < ApplicationComponent
  haml_template <<~HAML
    - if @profile
      - if @size == "sm" && content?
        - @display_name = nil
      .d-flex.justify-content-start.align-items-center
        .flex-shrink-0
          = v.avatar(@profile, size: @icon_size)
        .flex-grow-1.ms-1.lh-sm
          - if @display_name
            %div.m-0{class: @name_class}= @display_name
          - if @url
            = link_to(@username, @url, data: @data, class: @link_class)
          - else
            = @username
          - if content?
            %div= content
  HAML

  #
  # size: sm, md, or lg
  # stretch: true, false
  # turbo: true, false
  #
  def initialize(profile, size: "md", turbo: false, stretch: false, **args)
    super(**args)

    @size = size.to_s
    if @size == "sm"
      @name_class = "fw-bold lh-1"
      @icon_size = 38
    elsif @size == "md"
      @name_class = "fs-4 fw-bold lh-1"
      @icon_size = 64
    else
      @name_class = "fs-3 fw-bold lh-1 mb-1"
      @icon_size = 96
    end

    @profile = profile
    @username = if profile.respond_to?(:username)
      "@#{profile.username}"
    elsif profile.respond_to?(:name)
      profile.name
    end
    @display_name = profile.respond_to?(:display_name) && profile.display_name

    @url = args.delete(:url)
    @link_class = stretch ? "stretched-link" : ""
    if turbo === false
      @data["turbo-frame"] = "_top"
    end
  end
end
