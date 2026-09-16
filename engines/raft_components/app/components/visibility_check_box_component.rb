#
#
# creates a checkbox that controls the visibility of the content passed to the component
#
# <div class="form-check mb-3">
#   <input name="NAME" type="hidden" value="0" autocomplete="off">
#   <input class="visibility-toggle form-check-input" type="checkbox" value="1" checked="CHECKED" name="NAME" id="ID">
#   <label class="form-check-label" for="ID">LABEL</label>
#   <div class="visible-when-checked">
#     ...
#   </div>
# </div>
#
# for this to work, it requires this CSS
#
# .visibility-toggle         ~ .visible-when-unchecked { display: block }
# .visibility-toggle:checked ~ .visible-when-unchecked { display: none }
# .visibility-toggle         ~ .visible-when-checked   { display: none }
# .visibility-toggle:checked ~ .visible-when-checked   { display: block }
#
class VisibilityCheckBoxComponent < ApplicationComponent
  erb_template <<-ERB
    <div class="form-check mb-3">
      <input name="<%= @name %>" type="hidden" value="0" autocomplete="off">
      <input class="visibility-toggle form-check-input" type="checkbox" value="1" <%= @checked %> name="<%= @name %>" id="<%= @id %>">
      <label class="form-check-label" for="<%= @id %>"><%= @label %></label>
      <div class="<%= @content_class %> mt-2" style="margin-left: -1.5em">
        <%= content %>
      </div>
    </div>
  ERB

  def initialize(name:, label:, checked:, visible_when_checked: true)
    @label   = label
    @name    = name
    @id      = name.gsub(/\[\]/, '_')
    @checked = checked ? 'checked="checked"' : ''
    @content_class = visible_when_checked ? 'visible-when-checked' : 'visible-when-unchecked'
  end
end
