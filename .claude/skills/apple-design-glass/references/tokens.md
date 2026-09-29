# Design Tokens — the drop-in Apple theme layer

The token layer is the foundation no competing web skill ships. `assets/tokens.css` is the **source of truth**: real Apple system values (colors, type, spacing, radii, shadows, materials, motion) as CSS custom properties, with dark mode and the `prefers-*` fallbacks wired in. Reference the tokens in every component instead of hardcoding values — that's what makes a whole UI feel coherent and theme-able.

## How to use it

**Plain CSS / any framework:**
```css
@import "tokens.css";

.card {
  background: var(--bg-tertiary);
  color: var(--label);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-2);
  padding: var(--space-5);
}
```

**Tailwind v4:** import `tokens.css` then `tailwind.css` (the `@theme` bridge). Now use utilities — `bg-bg-secondary text-label rounded-lg shadow-2 p-5` — all backed by the same custom props, so dark mode still flows through. See `assets/tailwind.css`.

**CSS-in-JS:** read the custom props (`var(--label)`) in your styled templates; they cascade and respond to theme changes for free.

## What's in the layer (and why these exact numbers)

| Group | Tokens | Source |
|---|---|---|
| Color — accents | `--blue`…`--brown` (12 Apple system colors, light+dark) | Apple HIG system palette |
| Color — grays | `--gray-1`…`--gray-6` | Apple systemGray 1–6 |
| Color — semantic | `--label*`, `--bg*`, `--separator*`, `--fill-1..4` | Apple semantic colors (opacity-encoded hierarchy) |
| Type | `--font-*`, `--text-*` scale, `--tracking-*`, `--leading-*`, `--weight-*` | SF text styles (see `typography.md`) |
| Spacing | `--space-1`…`--space-12` (4/8pt grid) | Apple 8pt layout grid |
| Radii | `--radius-xs`…`--radius-2xl`, `--radius-capsule` | iOS corner scale |
| Elevation | `--shadow-1`…`--shadow-4`, `--shadow-glass` | soft layered shadows |
| Materials | `--material-*-tint`, `--material-blur`, `--material-saturate` | see `liquid-glass.md` |
| Motion | `--ease-*`, `--duration-*` | see `motion-physics.md` |

**Why opacity-encoded labels?** Apple doesn't define secondary text as a fixed gray — it's the ink color at reduced opacity (`rgba(60,60,67,0.6)` in light). That way text hierarchy holds over *any* background, including glass. Always pick `--label` / `--label-secondary` / `--label-tertiary` by role; never hardcode a gray for text.

**Why two-layer shadows?** A single shadow looks like a sticker. Apple elevation is a tight contact shadow + a soft ambient one, both low-opacity. The scale (`--shadow-1`→`4`) reads as increasing height; `--shadow-glass` is the floating-chrome variant.

## Dark mode

Two mechanisms, both built in:
- **Automatic:** `@media (prefers-color-scheme: dark)` remaps every semantic token.
- **Forced:** set `data-theme="dark"` (or `"light"`) on any ancestor to override the OS. Useful for a theme toggle or a dark hero section on a light page.

Never hardcode `#fff`/`#000` — use `--bg`/`--label` so both modes and forced themes just work. Note Apple's dark backgrounds are true black (`#000`) at the base with elevated surfaces stepping *up* in lightness (`#1C1C1E`, `#2C2C2E`) — the inverse of light mode, where elevation gets brighter/whiter.

## Continuous corners (the squircle detail)

iOS corners aren't circular arcs — they're **continuous curvature** (a superellipse / "squircle"), which looks softer and more organic than `border-radius`. Plain `border-radius` is a good-enough approximation at small sizes, but for large hero cards and app-icon-style elements the difference is visible. Two ways to get true continuous corners on the web:

```css
/* Option A — Safari/iOS only, native and cheap: */
.squircle { border-radius: var(--radius-xl); -webkit-corner-smoothing: 60%; }

/* Option B — cross-browser, via the CSS paint API (Houdini) or an SVG clip-path
   generated from a superellipse. Reserve for a few hero elements; it's heavier. */
```

For 95% of UI, `border-radius` with the token scale is correct — reach for the squircle only where a large rounded surface is the visual centerpiece.

## Extending the layer

- **Brand accent:** override `--accent` (defaults to `--blue`) at `:root` or on a subtree to retint the whole UI, including tinted glass.
- **Custom material thickness:** add a `--material-<name>-tint` pair following the existing ones; keep tint opacity and blur in step (thicker = more opaque + more blur).
- Keep additions semantic (name by *role*, not by value) so dark mode and theming keep working.
