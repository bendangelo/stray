---
name: icons
description: Use Phosphor icons in Rails views via the phosphor_icon helper. Never inline raw SVG in ERB.
---

# Phosphor Icons

Stray uses the `phosphor_icons` gem, which provides a `phosphor_icon` view helper that renders inline SVG server-side. It works with any asset pipeline (Propshaft + importmap + Tailwind here) because nothing ships to the browser except the inlined `<svg>`.

## Rule

**Never inline raw `<svg>` in ERB.** Always use the `phosphor_icon` helper.

## Usage

```erb
<%= phosphor_icon "house", class: "h-5 w-5" %>
<%= phosphor_icon "magnifying-glass", style: :bold, class: "size-4" %>
<%= phosphor_icon "x-circle", style: :duotone, class: "size-5 text-red-500" %>
```

## Options

- **`style:`** — Phosphor weight. One of `:regular` (default), `:bold`, `:light`, `:duotone`, `:fill`, `:thin`.
- **`class:`** — Tailwind classes. The gem sets `fill="currentColor"`, so size and color are controlled entirely via Tailwind:
  - Size: `w-5 h-5`, `size-4`, `w-3.5 h-3.5`, etc.
  - Color: `text-carrot-600`, `text-charcoal`, `text-amber-500`, etc.
- **`height:` / `width:`** — Optional numeric natural size (default 24). Prefer Tailwind `w-* h-*` classes instead.

## Finding icon names

Look up names at https://phosphoricons.com. The gem's symbol keys match the Phosphor site's kebab-case names (e.g. `magnifying-glass`, `caret-left`, `star`, `x`, `list`).

## Common icons used in Stray

| Purpose | Call |
|---|---|
| Hamburger / menu | `phosphor_icon "list", class: "w-6 h-6"` |
| Search | `phosphor_icon "magnifying-glass", style: :bold, class: "w-5 h-5"` |
| Close | `phosphor_icon "x", class: "w-3.5 h-3.5 inline-block"` |
| Previous | `phosphor_icon "caret-left", class: "w-full h-full"` |
| Next | `phosphor_icon "caret-right", class: "w-full h-full"` |
| Saved (filled) | `phosphor_icon "star", style: :fill, class: "w-3.5 h-3.5 inline-block"` |
| Save (outline) | `phosphor_icon "star", class: "w-3.5 h-3.5 inline-block"` |

## Adding a new icon

1. Confirm the name exists at phosphoricons.com (kebab-case).
2. Use it via `phosphor_icon` — no vendoring, no asset step, no importmap pin needed.
3. If the name is missing from the gem, verify against `PhosphorIcons::ICON_SYMBOLS` before assuming a typo.

## Verification

- `bin/rubocop` after editing ERB.
- `bin/rails test` to confirm views render.
