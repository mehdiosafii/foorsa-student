# Liquid Glass & Apple Materials on the Web

Apple's material language (refined into **Liquid Glass** at WWDC 2025 / iOS 26) is the single most-recognizable part of the aesthetic — and the part every other skill either hand-waves ("blur 20–40px") or implements only in SwiftUI (`glassEffect()`). This file gives you the **rendered CSS/SVG recipe**, tuned per element, with correct fallbacks.

## The mental model: glass is *layers*, not a blur

A real Apple material is **four stacked optical effects**, not one `backdrop-filter`. Getting all four is what separates "Apple 2025" from "glassmorphism 2020":

1. **Translucency** — a tint color you can see through (`background: rgba(...)`).
2. **Backdrop blur + saturation boost** — content behind is blurred *and* its colors are pushed (`backdrop-filter: blur() saturate()`). The saturation boost is what makes glass feel *lit* rather than frosted.
3. **Specular highlight** — a bright inset rim on the top edge where light "catches" the material, plus a subtle inner glow. This is the detail everyone omits.
4. **Depth shadow** — a soft outer drop shadow so the glass floats above content, plus a hairline rim so the edge reads against any background.

Optionally, a fifth for hero elements:

5. **Refraction / lensing** — the background *bends* at the edges (an SVG displacement filter), the thing that makes iOS 26 glass look wet rather than flat.

## Thickness → numbers (use the token that matches the job)

Material thickness encodes hierarchy. Thicker = more opaque, more separated from content. Pick by role, not by taste:

| Role | Tint opacity | Blur | Saturate | Token |
|---|---|---|---|---|
| Ultra-thin (subtle overlay, hover) | 0.44 | 10–12px | 160% | `--material-ultrathin-tint` |
| Thin (small chips, controls) | 0.60 | 12–16px | 170% | `--material-thin-tint` |
| **Regular (nav/tab/toolbars — the default)** | 0.72 | 20px | 180% | `--material-regular-tint` |
| Thick (sheets, sidebars, menus) | 0.84 | 30–40px | 180% | `--material-thick-tint` |

Larger surfaces want **more blur and a deeper shadow**; small chips want less blur so they don't smear. Never stack two translucent surfaces directly on top of each other — the double-blur muddies both. Put an opaque layer between them.

## Recipe 1 — The standard glass surface (production default)

This is the one to reach for 90% of the time: nav bars, toolbars, floating cards, menus. Works in every modern browser.

```css
.glass {
  /* 1. translucency */
  background: var(--material-regular-tint);
  /* 2. blur + saturation boost (saturate is what makes it feel lit) */
  -webkit-backdrop-filter: blur(20px) saturate(180%);
          backdrop-filter: blur(20px) saturate(180%);
  /* 3. specular highlight (inset top rim) + 4. hairline rim + outer depth */
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.55),   /* light catching the top edge */
    inset 0 0 0 0.5px rgba(255, 255, 255, 0.18),/* faint inner glow all around */
    0 0 0 0.5px rgba(0, 0, 0, 0.06),            /* hairline rim vs background */
    var(--shadow-glass);                        /* soft outer float */
  border-radius: var(--radius-lg);
}

/* Dark mode: the top-edge highlight is dimmer and the rim flips to light. */
@media (prefers-color-scheme: dark) {
  .glass {
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.12),
      inset 0 0 0 0.5px rgba(255, 255, 255, 0.06),
      0 0 0 0.5px rgba(0, 0, 0, 0.4),
      var(--shadow-glass);
  }
}
```

**Why the inset top highlight matters:** Apple's materials always render a bright edge where the surface meets light from above. Without it, translucent panels look like flat semi-transparent rectangles. This one line is the highest-leverage detail in the whole file.

## Recipe 2 — Vibrancy (legible text/icons on glass)

Text on translucent glass must stay readable over *any* background. Apple does this with **vibrancy**: content adopts the material's luminance rather than a fixed color. On the web, approximate it two ways:

```css
/* Simple + robust: semantic label tokens already encode the right opacity. */
.glass .title { color: var(--label); }
.glass .subtitle { color: var(--label-secondary); }

/* Richer: let icons/dividers blend with what's behind the glass. */
.glass .icon {
  color: var(--label);
  mix-blend-mode: plc-luminosity; /* see note */
}
```

> Note: `mix-blend-mode: luminosity`/`plus-lighter` on glass children gives a true vibrancy feel but is background-dependent — test it. For body copy, prefer the plain `--label*` tokens (never drop text below `--label-secondary` opacity on glass, or it fails contrast).

## Recipe 3 — Liquid Glass with refraction (hero elements only)

The iOS-26 "wet glass" look — where the background lenses and distorts at the panel's edges — needs an **SVG displacement filter** fed into `backdrop-filter`. This is expensive and currently **Chromium-only** as a backdrop input, so treat it as progressive enhancement layered on top of Recipe 1.

```html
<!-- Define the filter once, anywhere in the document (visually hidden). -->
<svg width="0" height="0" style="position:absolute">
  <filter id="liquid-refraction" x="-20%" y="-20%" width="140%" height="140%">
    <!-- turbulence = the distortion field; low frequency = gentle lensing -->
    <feTurbulence type="fractalNoise" baseFrequency="0.008 0.012"
                  numOctaves="2" seed="4" result="noise"/>
    <feGaussianBlur in="noise" stdDeviation="2" result="soft"/>
    <!-- displace the backdrop by the noise; scale controls bend strength -->
    <feDisplacementMap in="SourceGraphic" in2="soft" scale="18"
                       xChannelSelector="R" yChannelSelector="G"/>
  </filter>
</svg>
```

```css
.glass--liquid {
  background: var(--material-regular-tint);
  -webkit-backdrop-filter: blur(16px) saturate(180%);
          backdrop-filter: blur(16px) saturate(180%) url(#liquid-refraction);
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,0.55),
    inset 0 -1px 1px rgba(255,255,255,0.10),
    0 0 0 0.5px rgba(0,0,0,0.06),
    var(--shadow-glass);
  border-radius: var(--radius-xl);
}

/* Feature-detect; browsers that ignore the url() filter still get clean glass. */
@supports not (backdrop-filter: url(#liquid-refraction)) {
  .glass--liquid { backdrop-filter: blur(16px) saturate(180%); }
}
```

Keep `scale` restrained (12–20). Above ~25 it stops looking like glass and starts looking like a funhouse mirror. Reserve this for one or two hero moments per screen — the whole point of Apple materials is restraint.

## Recipe 4 — Dynamic tint ("stained glass")

Liquid Glass can pick up a color from its context (a colored button, a media background). Layer a color wash *under* the tint with a blend mode:

```css
.glass--tinted {
  position: relative;
  background: var(--material-thin-tint);
  -webkit-backdrop-filter: blur(18px) saturate(180%);
          backdrop-filter: blur(18px) saturate(180%);
}
.glass--tinted::before {
  content: "";
  position: absolute; inset: 0;
  border-radius: inherit;
  background: var(--accent);
  opacity: 0.14;
  mix-blend-mode: plus-lighter; /* brightens like tinted glass, not paint */
  pointer-events: none;
}
```

## Scroll-edge effect (not a hard divider)

Apple never separates translucent chrome from content with a 1px line. Instead the chrome's edge **fades content out** behind it with a mask/gradient, so scrolling content dissolves under the bar. Do this instead of `border-bottom`:

```css
.nav-scrim {
  position: sticky; top: 0;
  height: 12px;                 /* the fade zone below the glass bar */
  background: linear-gradient(var(--bg), transparent);
  -webkit-mask-image: linear-gradient(black, transparent);
}
```

## Animating materials — "materialize, don't fade"

When a glass surface appears, don't just fade opacity. Animate the **blur radius and scale together** so it feels like the material condenses into place — the Apple "materialize" motion. See `motion-physics.md` for the spring, but the property pairing is:

```css
/* from */ { backdrop-filter: blur(0);   transform: scale(0.96); opacity: 0; }
/* to   */ { backdrop-filter: blur(20px); transform: scale(1);    opacity: 1; }
```

Animating `backdrop-filter`'s blur is GPU-heavy; keep these short (≤300ms) and only on entrance, never on a loop.

## Accessibility & fallbacks — non-negotiable

Glass fails three ways for real users. Handle all three:

```css
/* 1. No backdrop-filter support (older Firefox): fall back to a solid-ish bg. */
@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
  .glass { background: color-mix(in srgb, var(--bg) 88%, transparent); }
}

/* 2. User reduces transparency (also helps low-vision + saves battery). */
@media (prefers-reduced-transparency: reduce) {
  .glass, .glass--liquid, .glass--tinted {
    background: var(--bg);
    -webkit-backdrop-filter: none;
            backdrop-filter: none;
  }
}

/* 3. User wants more contrast: add a real border so edges are unambiguous. */
@media (prefers-contrast: more) {
  .glass { box-shadow: 0 0 0 1px var(--label); }
}
```

Two more rules that matter:
- **Contrast still applies through glass.** Body text on a material must clear 4.5:1 against the *effective* rendered background, not the tint alone. When in doubt, thicken the material.
- **`saturate()` can shift brand colors.** If a logo sits on glass, exclude it from the vibrancy blend.

## Checklist for any glass surface

- [ ] Tint + blur + **saturate** (not blur alone)
- [ ] Inset top-edge specular highlight present
- [ ] Hairline rim so the edge reads on any background
- [ ] Soft outer shadow for float/depth
- [ ] `-webkit-` prefix on `backdrop-filter` (Safari)
- [ ] Not stacked directly over another translucent surface
- [ ] `@supports` fallback + `prefers-reduced-transparency` + `prefers-contrast`
- [ ] Text stays ≥ `--label-secondary`; verify 4.5:1
- [ ] Refraction (`url(#...)`) only on 1–2 hero elements, Chromium-gated
