#
# ACTIONBAR
#
# A toast that is positioned at the bottom of the content
# with left margin set to --sidebar-actual-width
#
#
# = v.actionbar do
#   = "content"
#
#
class ActionbarComponent < ApplicationComponent
  renders_one :header_label
  renders_one :header

  haml_template <<~HAML
    .actionbar.fixed-bottom.d-flex{data: @data, class: @html[:class]}
      .toast.w-100.show(role="alert" data-bs-autohide="false" aria-live="assertive" aria-atomic="true")
        - if @label || header?
          .toast-header
            - if @label
              .label.me-1= @label
            - if header?
              %b.me-auto= header
            -# %button(type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close")
        .toast-body.d-flex.align-items-center.gap-2
          = content
  HAML

  def initialize(label: nil, **kwargs)
    super
    @label = label
  end

end
