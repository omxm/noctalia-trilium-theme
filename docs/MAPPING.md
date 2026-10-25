# Color mapping

How Noctalia's palette maps onto Trilium's Next theme variables. The source of truth is
[`templates/trilium.css`](../templates/trilium.css); this page explains the choices.

Example values are from the **Gruvbox Material Medium** community palette.

## Approach

- The base is Trilium's own **Next** theme. Only its CSS variables are overridden, on `#trilium-app`
  (the `<body>`). Next's stylesheets load *after* a custom theme note, so overrides on `:root` would lose.
- Only the "solid" colors are overridden: backgrounds, text, borders, accents. Next's translucent
  white/black overlays (hover, inputs, buttons) are left alone; they adapt to any background.
- Every color comes from `colors.<name>.default`, i.e. Noctalia's current mode. Dark/light is handled by
  switching the note's `#appThemeBase` between `next-dark` and `next-light` (`push.sh` does this), so the
  Next base flips together with the palette.
- Translucent colors are written as `{{ colors.X.default.rgba | set_alpha N }}`. `set_alpha` on `.hex`
  silently drops the alpha.

## 0. Base, card, accent

Picked by screenshotting Noctalia's own settings window, bar and control center and comparing pixels.

| Variable | Used for | Noctalia | Where Noctalia uses it | Dark | Light |
|---|---|---|---|---|---|
| `--noctalia-base` | Tree, tab row, launcher, toolbar, status bar, right pane | `surface` | Window background, bar | `#282828` | `#fbf1c7` |
| `--noctalia-card` | Editor | `surface_variant` | Search field, tiles, unselected tabs | `#32302f` | `#f4e8be` |
| `--noctalia-accent` | Selected things | `primary` | Selected sidebar item, page heading, selected tab, toggles | `#a9b665` | `#6c782e` |
| `--noctalia-on-accent` | Text on the accent | `on_primary` | Same | `#282828` | `#fbf1c7` |

In light mode `surface_variant` is slightly darker than `surface`, so the card is slightly darker than the
base. Noctalia's own light UI looks the same way.

## 1. Backgrounds

| Trilium variable | Where | Noctalia |
|---|---|---|
| `--left-pane-background-color`, `--launcher-pane-*-background-color` | Tree, launcher | `--noctalia-base` |
| `--main-background-color` | Editor | `--noctalia-card` |
| `--modal-background-color`, `--tool-dialog-background-color`, `--menu-background-color-no-backdrop`, `--board-column-background` | Dialogs, menus, boards | `surface_container` |
| `--menu-background-color` | Context menus, dropdowns | `surface_container` alpha 0.85 |
| `--select-focus-background`, `--note-icon-background-color`, `--help-kbd-shortcut-background`, `--calendar-coll-event-background-color` | Raised elements | `surface_container_high` |
| `--note-tooltip-background-color`, `--right-pane-peek-background` | Note previews | `surface_container_high` alpha 0.85 |
| `--floating-button-background-color` | Floating buttons | `surface_container_high` alpha 0.82 |
| `--accented-background-color`, `--note-icon-hover-background-color`, `--button-group-active-button-background-color`, `--help-code-background` | Emphasis | `surface_container_highest` |
| `--tooltip-background-color`, `--toast-background` | Tooltips, toasts | `surface_container_highest` alpha 0.9 |
| `--launcher-pane-horiz-border-color` | Launcher edge | `shadow` |

## 2. Text

| Trilium variable | Noctalia |
|---|---|
| `--main-text-color`, `--menu-text-color`, `--input-text-color`, `--hover-item-text-color`, `--tooltip-foreground-color`, `--toast-text-color` | `on_surface` |
| `--muted-text-color`, `--left-pane-text-color`, `--left-pane-icon-color`, launcher text, menu/note/tab icons, dialog and right-pane headings | `on_surface_variant` |
| `--inactive-tab-text-color` | `outline` |
| `--left-pane-item-selected-color`, `--active-tab-text-color`, `--active-tab-icon-color` | `on_primary` |

## 3. Borders

| Trilium variable | Noctalia |
|---|---|
| `--main-border-color`, `--dropdown-border-color` | `outline_variant` |
| `--subtle-border-color` | `surface_container_high` |
| `--gutter-hover-color` | `outline` |
| `--scrollbar-thumb-color` / `--scrollbar-thumb-hover-color` | `outline` alpha 0.7 / `on_surface_variant` alpha 0.6 |

## 4. Accents

| Trilium variable | Noctalia |
|---|---|
| `--left-pane-item-selected-background` (selected tree item) | `primary`, solid |
| `--active-tab-background-color` (selected tab; section 8, optional) | `primary`, solid |
| `--input-focus-outline-color` | `primary` alpha 0.6 |
| `--selection-background-color` | `primary` alpha 0.35 |
| `--active-item-background-color` | `primary_container` |
| `--link-color` / hover / selection outline | `tertiary` / alpha 0.14 / alpha 0.5 |
| `--quick-search-result-highlight-color` / fuzzy | `primary` / `secondary` |
| `--contextual-help-icon-color` | `tertiary` |
| `--task-checkbox-done-color`, `--protected-session-active-icon-color`, update badge | `primary` (badge text `on_primary`) |
| Switches that are on (layout layer) | `primary` track, `on_primary` thumb |

## 5. Errors

| Trilium variable | Noctalia |
|---|---|
| `--tab-close-button-hover-background` / `-color` | `error` / `on_error` |
| `--dropdown-item-icon-destructive-color`, `--task-checkbox-unknown-state-color`, `--sync-status-error-pulse-color`, `--board-limit-exceeded-background` | `error` |
| `--badge-read-only-background-color` | `error_container` |

## 6. Search expression highlighting

Uses the terminal colors: keyword = magenta, label = blue, literal = yellow, string = green,
negation = red, property = cyan, relation = bright magenta, operator and bracket = `outline`.

## 7. Backdrop saturation

Next blurs whatever is behind menus with `blur(20px) saturate(6)` (and `saturate(1000%)` for floating icon
buttons). On a tinted background that turns menus neon yellow, so only the blur is kept.

## 9. Alias variables

Next declares many variables on `:root` as `var(--something-else)`, e.g.
`--root-background: var(--left-pane-background-color)`. `var()` resolves on the element that declares it,
so on `:root` these keep Next's values no matter what is overridden on `#trilium-app`. The template
re-declares every such alias (collected mechanically from Trilium 0.106.0's stylesheets, including the
component stylesheets) with the same expression, so they follow the overrides. Four aliases whose
expressions differ between dark and light are left alone.

## Not changed

- Translucent overlays for hover, inputs, buttons and cards.
- Shadows, the log viewer colors, the space usage colors, badge category colors.
- Syntax highlighting. Code notes and code blocks use Trilium's own code themes
  (Options -> Appearance), not CSS variables.
