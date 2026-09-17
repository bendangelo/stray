# Bare-Shade Color Bug Fix

**Date:** 2026-09-17
**Status:** Approved
**Prerequisite for:** [Consistent Design System & Mobile UX](2026-09-17-consistent-design-system-design.md)

## Goal

Fix the silent rendering bug where 408 bare-shade color utilities (e.g. `text-charcoal`, `border-charcoal`, `text-cerise`, `bg-champagne`) resolve to nothing because Tailwind v4 only generates utilities from the *numbered* color scales defined in `@theme`. Restoring them changes the app from its current accidental rendering (white body, browser-default danger text, invisible drawer backdrop) to the intended champagne/charcoal/cerise palette.

## Problem

`app/assets/tailwind/application.css` defines each palette with numbered shades only:

```css
--color-charcoal-50: #868686;
...
--color-charcoal-600: #0E0E0E;
--color-cerise-50: #F6D1DE;
...
--color-cerise-500: #D9376E;
```

In Tailwind v4, a bare utility like `text-charcoal` is only generated when a `--color-charcoal` variable exists. It does not, so the utility is silently skipped at build time. Verified against the compiled output (`bin/rails tailwindcss:build` then grep of `app/assets/builds/tailwind.css`): `.text-charcoal`, `.border-charcoal`, `.text-cerise`, `.border-cerise`, `.bg-champagne`, `.bg-charcoal`, `.text-carrot`, `.border-carrot`, `.text-champagne`, `.bg-cerise`, and `.ring-charcoal` are all absent. Only `.bg-mint` exists (via the unnumbered `--color-mint: #85d699`).

Usage counts in views/helpers: `text-charcoal` ×202, `border-charcoal` ×146, `text-cerise` ×35, `border-cerise` ×12, `bg-mint` ×4 (working), `text-carrot` ×3, `text-champagne` ×2, `bg-charcoal` ×2, `bg-champagne` ×2, `ring-charcoal` ×1, `border-carrot` ×1, `bg-cerise` ×1.

### Visible symptoms today

- `<body class="bg-champagne">` (layouts/application.html.erb:24) renders transparent/white — the warm `#F8F2E8` app background never appears.
- All danger/delete text (`text-cerise`) renders in browser-default link blue/black, not pink-red `#D9376E`.
- Flash alert borders (`border-cerise`), the delete-button border on source show, and tag-bar active underline (`border-carrot`) are missing.
- The mobile sidebar drawer backdrop (`bg-charcoal/50`, layouts/application.html.erb:41) is invisible — the drawer overlays content with no dimming.
- The unseen-dot ring (`ring-charcoal/50`, items/_item.html.erb:31) is missing.
- Source letter avatars (`bg-charcoal` in images_helper.rb:27) render on a transparent square instead of a dark one.

Note: `charcoal/50` opacity modifiers also fail for the same reason (no base `--color-charcoal` to hang the alpha on).

## Design

**Approach: add the missing base color variables to `@theme`** (the approved choice) rather than sweeping 408 usages to numbered shades.

For each palette, add one unnumbered variable that acts as the scale's default. Values follow the existing convention (base = the "primary" step of the scale, consistent with the existing `--color-mint: #85d699`):

```css
--color-charcoal: #2A2A2A;   /* = charcoal-500; body ink */
--color-champagne: #F8F2E8;  /* = champagne-500; app background */
--color-athens: #fffffe;     /* = athens-400; card surface */
--color-carrot: #FF8E3C;     /* = carrot-500; accent */
--color-cerise: #D9376E;     /* = cerise-500; danger */
--color-amber: #fbbd23;      /* = amber-500; warning */
--color-teal: #349d86;       /* = teal-500 */
--color-sky: #7d98f2;        /* = sky-500 */
--color-cotton: #d058ee;     /* = cotton-500 */
```

`--color-mint: #85d699` already exists (application.css:88) — no change needed.

With these present, Tailwind v4 generates every bare form used in the codebase (`text-charcoal`, `border-charcoal`, `ring-charcoal`, `bg-charcoal` and all their opacity-modifier forms like `bg-charcoal/50`, `ring-charcoal/50`, `bg-cerise/10`), and the utilities appear in the compiled CSS.

**Out of scope (handled later in the design-system plan):**

- Off-palette colors (`text-stone-600`, `text-blue-600`, `text-gray-800/500`, `bg-red-100`, `bg-yellow-100`, `.dot-*` hexes) — those are sweep targets, not token bugs.
- Any markup, tap-target, or component changes.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Fix via `@theme` base variables, not a 408-usage sweep | One 9-line change makes every bare utility resolve; sweeping all views is massive churn with identical result |
| 2 | Base values mirror the -500 (or existing base) step of each scale | Matches `--color-mint` precedent; -500 is each palette's primary tone; keeps numbered shades untouched |
| 3 | Accept the resulting visual changes as intended behavior | Today's white body / black danger text is the bug; champagne body, pink-red danger, visible backdrop are what the palette was designed to do (user-approved) |

## Testing

- Helper/system suite stays green — no class *names* change, only their CSS definitions.
- New system test asserting the compiled stylesheet defines the bare utilities: build Tailwind, then in a system test assert `getComputedStyle` resolves `text-charcoal` on body copy (`rgb(42, 42, 42)`), `bg-champagne` on body (`rgb(248, 242, 232)`), and that the drawer backdrop has a non-transparent background.
- Manual verification step: `bin/rails tailwindcss:build` then grep the build output for `.text-charcoal{`, `.bg-champagne{`, `.bg-charcoal\/50`, `.text-cerise{`.