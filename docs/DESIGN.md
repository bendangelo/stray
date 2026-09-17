# Stray Design System

Single source of truth for UI conventions. The palette lives in `app/assets/tailwind/application.css` (`@theme`); behavior classes live in the same file below `mark`.

## Tokens

- **Surfaces:** `bg-champagne` (app background), `bg-champagne-50` (navbar/sidebar), `bg-athens-400` (cards/inputs/menus), `bg-athens-500` (hover grey)
- **Ink:** `text-charcoal` (body), `text-charcoal-300` (secondary), `text-charcoal-600` (headings via `font-display`)
- **Accent:** carrot — `bg-carrot-500` (primary buttons), `bg-carrot-100` (menu hover tint), `text-carrot-600` (links)
- **Danger:** cerise. **Success/new:** mint. **Provenance dots:** sky / mint / charcoal-300.

## Rules

1. **44px minimum tap target** on every interactive control (`min-h-11` / `min-w-11` or CSS floor). Table-row links may go down to 36px only when the whole row is not clickable.
2. **Buttons:** always `ui_button(variant:, size:)` — `border-3 border-charcoal`, heights h-9/h-11/h-12. Never hand-roll `border-2` or `bg-white` buttons.
3. **Inputs:** always `ui_input` (h-11) / `ui_select` / `ui_label`.
4. **Dropdowns:** always `render "shared/ui/dropdown", menu_id:, trigger_label:, trigger_class:, trigger:, menu:, alignment:, menu_class:`. Menu items always `ui_menu_item` (or `ui_menu_item(danger: true)`).
5. **Menu hover = carrot-100 fill.** Never re-style per menu; the `.ui-menu-item` CSS owns hover/focus states.
6. **Cards:** `ui_card(padding:)`. Empty states: `render "shared/ui/empty_state", message:`.
7. **Flash:** `render "shared/ui/flash"` — never inline flash markup.
8. **Page widths:** `ui_page(tier:)` — `:form` max-w-3xl, `:list` max-w-6xl, `:reader` max-w-screen-xl. Feed page keeps its xl:max-w-screen-2xl exception.
9. **Icons:** `phosphor_icon` helper only. Menu icons `w-3.5 h-3.5`, trigger icons `w-4 h-4`.
10. **Never:** raw Tailwind palette colors (gray/blue/stone/red/yellow), `dark:` variants, inline SVGs, `border-2` on buttons/inputs.

## Adding a new dropdown (recipe)

1. `menu_id`: unique, e.g. `foo-menu-#{record.id}`.
2. Trigger: icon-only → `trigger_class: ui_dropdown_trigger`; labeled pill → custom string including `min-h-11`.
3. Items: `ui_menu_item` via `link_to`/`action_link_to`/`button_to`, icon `w-3.5 h-3.5` first, label text second.
4. Destructive item last, `ui_menu_item(danger: true)`, separated by `border-t-3 border-charcoal/10 my-1.5`.
