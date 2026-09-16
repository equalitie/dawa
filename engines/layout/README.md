# Layout

This layout is built using:

* Bootstrap 5
* SCSS
* HAML

# Structure

Visual structure:

```
+-----------------------+
| icon | .header-text   |  > %header
+------+----------------+
|      |                |  \
|.side |                |  |
| bar  |  article       |  |> %middle
|      |                |  |
|      |                |  |
|      |                |  /
+-----------------------+
|      | footer         |
+-----------------------+
```

HTML structure:

```haml
%html
  %head
  %body
    %header
      #header-icon
      #header-text
      #header-status
    %middle
      %aside.sidebar
      %main
        %nav.breadcrumbs
        %article
    %footer
```

# Dual-Mode Layout System

## Mode 1: Normal Flow (Browser Scroll)

Behavior: The page uses the browser's native viewport scrolling. Content expands naturally down the page, and the main browser scrollbar appears when content exceeds the viewport height.

How it works: No flex constraints are applied to the layout chain. Elements remain in the normal document flow where block-level components stack vertically and expand to their full content height. The body has no fixed height, allowing it to grow with content.

Use case: Standard web pages where the user expects traditional scrolling behavior (blog posts, documentation, marketing pages).

## Mode 2: Constrained Layout (Local Scroll)

Behavior: The browser window is locked (no viewport scrollbar). A specific container (.fill-scroll) handles scrolling internally, creating an application-like interface where only the content panel scrolls while headers and sidebars remain fixed.

How it works: Every container from body down to #content-body receives flex: 1 and min-height: 0, creating a constrained flex chain that establishes explicit heights. The .fill-scroll element then uses height: 100% and overflow-y: auto to create an independent scrolling region.

CSS implementation:
css

html, body { height: 100%; }
body { display: flex; flex-direction: column; height: 100vh; }
main, article, #content, #content-body { flex: 1; min-height: 0; }
.fill-scroll { height: 100%; overflow-y: auto; }

Use case: Application-style interfaces (dashboards, email clients, chat applications) where headers/toolbars should remain persistently visible.
The Switching Mechanism

The two modes are mutually exclusive and controlled by a single conditional variable (use_local_scroll). When true, Mode 2 CSS loads and the .fill-scroll wrapper is added to the DOM. When false, Mode 1 CSS loads and the .fill-scroll wrapper is omitted entirely.

# Reference

CSS Variables: https://getbootstrap.com/docs/5.2/customize/css-variables/

Sass Variables: https://github.com/twbs/bootstrap-rubygem/blob/master/assets/stylesheets/bootstrap/_variables.scss
