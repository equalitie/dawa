# Raft View Components

Raft applications use a custom component framework built on top of [ViewComponent](https://viewcomponent.org/).

## The `v` Helper

Components are instantiated through the `v` helper. This is available everywhere views are rendered:

- In Haml view templates (partials, pages)
- In other ViewComponent classes (since `ApplicationComponent` includes `ViewHelper`)
- In helpers that are included in the view context

The `v` helper returns a `ComponentFactory` instance. When you call `v.component_name(...)`, the factory:

1. Camelizes the method name (e.g. `dropdown_button` → `DropdownButtonComponent`)
2. Constantizes the class name to find the component class
3. Instantiates the component with the provided keyword arguments
4. Calls `render_in` on the component (optionally with a block)

```haml
= v.button(label: "Click Me", icon: "plus-lg", color: "success")
= v.dropdown_button(label: "Menu") do |menu|
  - menu.item { v.button(label: "Option 1") }
  - menu.item { v.button(label: "Option 2") }
```

These two are functionally equivalent: 

```erb
<%= render(MessageComponent.new(name: "World")) %>
```

```erb
<%= v.message(name: "World") %>
```

## Form Context

When a component is used inside a `form_with` block, the form builder is passed to the component factory. This allows components to:

- Know the form's object name and generate correct input names
- Access the form's record for default values

This is achieved via the `BuilderHelper` which creates the factory with a `builder:` reference:

```haml
= form_with(model: @task) do |form|
  = form.v.text_field :title      # generates name="task[title]"
  = form.v.submit_button          # submits this form
```

When a component with `hidden_form = true` is used inside a form builder context, its hidden form is placed into `content_for(:hidden_content)` instead of inline (since nesting `<form>` tags is invalid HTML). The response must render `<%= content_for(:hidden_content) %>` for this to work.

## Common Arguments (all components)

All components accept these keyword arguments via `ApplicationComponent#initialize`:

| Argument   | Type   | Description |
|------------|--------|-------------|
| `:id`      | String | The element's DOM id |
| `:class`   | String | CSS class(es), merged with any existing classes |
| `:style`   | String | CSS style string, appended to any existing styles |
| `:html`    | Hash   | Raw HTML attributes, merged directly onto the element. e.g. `html: { style: "width: 100%" }` |
| `:data`    | Hash   | Data attributes (rendered as `data-*`). Used for Stimulus controllers, Bootstrap toggles, etc. |
| `:params`  | Hash   | Additional parameters included in any request made by the component (e.g. a hidden form) |
| `:name`    | String | Name attribute for input elements |
| `:disabled`| Boolean| Disables the component if true |
| `:hide`    | Boolean| If true, `display: none` is added to the element's style |
| `:tooltip` | String | Tooltip text; sets `data-bs-toggle="tooltip"` and `data-bs-title` automatically |

## Button Components

### Class Hierarchy

```
ApplicationComponent
  └── ButtonComponent (abstract superclass)
        ├── AutocompleteButtonComponent
        ├── CancelButtonComponent
        ├── CancelButtonLinkComponent
        ├── CloseModalButtonComponent
        ├── CreateButtonComponent
        ├── DeleteButtonComponent
        ├── DropdownButtonComponent
        │     └── DropdownDotsComponent
        ├── GetButtonComponent
        ├── LinkButtonComponent
        ├── MiniButtonComponent
        ├── ModalButtonComponent
        ├── PostButtonComponent
        ├── RemoteModalButtonComponent
        ├── RemoteModalLinkComponent
        ├── SlideButtonComponent
        ├── SubmitButtonComponent
        │     └── SaveButtonComponent
        └── UpdateButtonComponent
```

### ButtonComponent Arguments

All button components accept these additional arguments (on top of common args):

| Argument     | Type    | Default  | Description |
|-------------|---------|----------|-------------|
| `label`     | String  | class default | Button text label |
| `icon`      | String  | class default | Bootstrap icon name (e.g. `"plus-lg"`, `"trash"`, `"pencil"`) |
| `color`     | String  | `"dark"`  | Bootstrap color name (`"primary"`, `"success"`, `"danger"`, `"dark"`, etc.) |
| `size`      | String  | `nil`     | Bootstrap button size (`"sm"`, `"lg"`) |
| `fill`      | Boolean | `false`   | If true, uses solid `btn-{color}`. If false (default), uses `btn-outline-{color}` |
| `border`    | Boolean | `true`    | If false, renders as a link-style button without border/fill |
| `display`   | String  | `"button"`| `"button"`, `"link"`, or `"text"` |
| `url`       | String  | `nil`     | URL for navigation or form action |
| `method`    | String  | class default | HTTP method for the form (`:put`, `:post`, `:delete`, `:get`) |
| `action`    | String  | `nil`     | Rails action-like shorthand |
| `spin`      | Boolean | `nil`     | If true, shows a spinner when disabled |
| `image`     | String  | `nil`     | Image path, rendered alongside the label |
| `override`  | Hash    | `nil`     | Raw HTML attributes that override `@html` entirely |
| `form_data` | Hash    | `nil`     | HTML data attributes for the generated hidden form |
| `hidden_form_inline` | Boolean | `nil` | Override form placement: true = inline, false = `content_for(:hidden_content)` |

### Class-level Defaults

Button component subclasses set class-level defaults:

```ruby
class DeleteButtonComponent < ButtonComponent
  self.button_type  = "submit"
  self.hidden_form  = true
  self.default_method = "delete"
  self.default_label = "components.delete"
  self.default_icon  = "trash"
  self.default_color = "dark"
end
```

The `hidden_form` class attribute determines whether the button generates its own `<form>` tag. When `hidden_form = true`:
- The component builds a hidden form with the specified URL, method, and params
- If used outside a form builder: the hidden form is rendered inline
- If used inside a form builder (e.g. `form_with do |f|`): the hidden form is placed in `content_for(:hidden_content)` to avoid nested forms

### Hidden Forms and Params

Button components with `hidden_form = true` build a hidden form that includes hidden field tags for each param:

```ruby
v.update_button(
  url: task_path(@task),
  params: { "task" => { "state" => "progress" } },
  label: "Progress"
)
```

This generates a hidden form with `<input type="hidden" name="task[state]" value="progress">`.

## Common Button Components Reference

### `v.button(...)`
The base button component. Renders a `<button>` element. No hidden form by default.

### `v.submit_button(...)`
Submits the enclosing form (inherits `button_type = "submit"`).

### `v.save_button(...)`
Like `submit_button`, but auto-generates a label like "Save Task" from the form's object name.

### `v.update_button(...)`
A standalone button with its own hidden form (`method: :put`). Used for quick actions outside a form context.

### `v.post_button(...)`
A standalone button with its own hidden form (`method: :post`).

### `v.delete_button(...)`
A standalone button with `method: :delete`. Used for destruction actions.

### `v.create_button(...)`
A standalone button with `method: :post`, labeled "Create" by default.

### `v.cancel_button(...)`
Like `delete_button` but with cancel styling.

### `v.cancel_button_link(...)`
A link styled as a cancel button (no hidden form).

### `v.link_button(...)`
A link styled as a button. Supports `target:` and `turbo:` options.

### `v.get_button(...)`
A standalone button with `method: :get`.

### `v.dropdown_button(...)`
A button that opens a dropdown menu. Supports two item patterns:

**Block pattern (for custom button components):**
```haml
= v.dropdown_button(label: "Actions") do |menu|
  - menu.item { v.button(label: "Edit", url: edit_path) }
  - menu.item { v.update_button(label: "Archive", url: archive_path, params: { ... }) }
```

**Slot pattern (for simple links/posts):**
```haml
= v.dropdown_button(label: "Actions") do |menu|
  = menu.with_item(label: "Edit", url: edit_path)
  = menu.with_item(label: "Archive", url: archive_path, params: { ... })
```

### `v.dropdown_dots(...)`
A compact dropdown with a three-dot icon. Same API as `dropdown_button`.

### `v.autocomplete_button(name, url:, ...)`
A button that opens a searchable autocomplete dropdown. On selection, submits the enclosing form with the chosen value. The `name` becomes the submitted parameter name.

### `v.close_modal_button(...)`
A button that closes a Bootstrap modal (`data-bs-dismiss="modal"`).

### `v.modal_button(...)`
A button that opens a modal dialog. Content is loaded via a Turbo Frame.

### `v.mini_button(...)`
A compact link-style button.

## Non-Button Components

### `v.box(...)`
A card-like container (defaults to non-colored, no close button). Supports:
- `box.with_buttons(position)` — renders buttons aligned to the right
- `box.with_footer` — renders a card footer
- `box.with_header` — renders a card header
- `box.with_list_item` — adds items to a list group inside the box

```haml
= v.box do |box|
  - box.with_buttons(:start) do
    = v.link_button(icon: "pencil", url: edit_path)
  Content here
  - box.with_list_item do
    .row
      .col = render "partial"
```

### `v.card(...)`
A Bootstrap 5 card. Supports `header`, `header_end`, `image`, `table`, `list`, and `footer` slots.

### `v.breadcrumbs(...)`
Bootstrap 5 breadcrumbs with a block-based API:
```haml
- breadcrumbs do |bc|
  - bc.with_crumb { link_to("Home", root_path) }
  - bc.with_crumb(active: true) { "Current Page" }
```

### `v.alert(...)`
A Bootstrap alert with customizable color and optional dismiss button.

### `v.paginate(...)`
Paginate component wrapping the collection.

### `v.avatar(...)`
Renders a user avatar (image or initials fallback).

### `v.profile(...)`
Renders a profile card with avatar and details.

### `v.offcanvas(...)`
A Bootstrap offcanvas panel.

### `v.expander(...)`
A collapsible/expandable section.

### `v.state_badge(...)`
A colored badge indicating state/status.

### `v.toggle_button(...)`
A checkbox styled as a toggle button.

### `v.copy(...)`
A button that copies content to the clipboard.

### `v.contain_image(...)`
An image container with proper aspect ratio containment.
