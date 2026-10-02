# Typography — Apple's optical detail

Type is where "looks Apple-ish" is won or lost, and it's the subtlest part. Apple's system (from *The Details of UI Typography*, WWDC 2020) is not a font choice — it's a set of **optical adjustments** that most sites skip. Get these four right and body text reads unmistakably Apple.

## 1. The font stack — SF via system fonts

You can't ship SF Pro as a webfont (license), but `-apple-system` pulls it natively on Apple devices, which is where the aesthetic matters most, and degrades cleanly elsewhere. The token layer sets this up:

```css
font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display",
  "Helvetica Neue", "Segoe UI", system-ui, sans-serif;
```

- **`font-optical-sizing: auto`** is essential — SF has two optical cuts, *Text* (tighter spacing, sturdier, for body) and *Display* (tighter tracking, refined, for large sizes). The OS swaps them by size automatically only if you opt in. Without this, large headings look slightly wrong.
- For a rounded, friendly feel (kids/health/playful apps) use **SF Pro Rounded** via `--font-rounded`. For editorial long-form, Apple pairs SF with the **New York** serif (`--font-serif`).
- Never substitute Inter/Roboto and call it Apple — the metrics differ. If you must use a webfont for cross-platform consistency, the closest is **Inter with `-apple-system` first in the stack** so Apple devices still get SF.

## 2. Tracking (letter-spacing) is size-specific — this is the big one

Apple **tightens letter-spacing as text gets larger** and relaxes it toward zero (or slightly positive) as it gets smaller. A single global `letter-spacing` is the #1 tell of a non-Apple site. Use the tokens:

| Size range | Tracking | Token |
|---|---|---|
| Large display (28pt+) | `-0.022em` | `--tracking-tight` |
| Titles (20–26pt) | `-0.014em` | `--tracking-snug` |
| Body (15–17pt) | `0` | `--tracking-normal` |
| Small (≤13pt) | `+0.01em` | `--tracking-wide` |

```css
.display { font-size: var(--text-large-title); letter-spacing: var(--tracking-tight); }
.body    { font-size: var(--text-body);        letter-spacing: var(--tracking-normal); }
.caption { font-size: var(--text-caption-1);   letter-spacing: var(--tracking-wide); }
```

## 3. Leading (line-height) moves *inversely* to size

Headlines get **tight** leading (lines nearly touching); body and captions get **looser** leading for readability. This is the opposite of what many web defaults do.

| Role | line-height | Token |
|---|---|---|
| Large headline | 1.05–1.1 | `--leading-tight` |
| Title | 1.2 | `--leading-snug` |
| Body UI | 1.3–1.4 | `--leading-normal` |
| Long-form reading | 1.5 | `--leading-relaxed` |

## 4. Hierarchy = weight + size + leading as a *set*

Apple's text styles are named bundles, not just sizes. A "headline" is 17pt **semibold** with tight leading; "body" is 17pt regular. Reproduce the ramp with the tokens rather than inventing sizes:

```css
.large-title { font-size: var(--text-large-title); font-weight: var(--weight-bold);
               letter-spacing: var(--tracking-tight); line-height: var(--leading-tight); }
.headline    { font-size: var(--text-headline); font-weight: var(--weight-semibold);
               line-height: var(--leading-snug); }
.body        { font-size: var(--text-body); font-weight: var(--weight-regular);
               line-height: var(--leading-normal); }
.footnote    { font-size: var(--text-footnote); color: var(--label-secondary);
               letter-spacing: var(--tracking-wide); }
```

Weights: Apple leans on **regular (400)**, **medium (500)**, and **semibold (600)**; bold (700) is for large titles only. Avoid light/thin weights for UI text — they fail contrast and legibility.

## 5. Fluid display type

For hero headings, scale with the viewport but cap it, and keep the tight optics:

```css
.hero-title {
  font-size: clamp(2rem, 5vw + 1rem, 4.25rem);
  font-weight: var(--weight-bold);
  letter-spacing: var(--tracking-tight);
  line-height: var(--leading-tight);
  font-optical-sizing: auto;
  text-wrap: balance;   /* even line lengths, Apple-marketing style */
}
```

## 6. Respect the user's text size

Use `rem`/`em` for font sizes *and* the spacing around text so layouts scale when a user bumps their base size (the web analog of Dynamic Type). Don't lock text in `px`. The token scale is already in `rem`.

## Tailwind note

If using Tailwind v4, map these into `@theme` (see `assets/tailwind.css`) so you get `text-body`, `tracking-tight`, `leading-tight` utilities backed by the same values. But the **size-specific tracking pairing** still has to be applied deliberately per element — Tailwind won't do the inverse tracking/leading relationship for you. Bake it into your component classes.

## The tells of non-Apple type (audit list)

- [ ] One global `letter-spacing` instead of size-specific tracking
- [ ] Large headings with default (loose) leading
- [ ] `font-optical-sizing` not set
- [ ] Thin/light weights on UI text
- [ ] Body text below `--label-secondary` contrast on colored/glass backgrounds
- [ ] Fixed `px` sizes that ignore user text scaling
- [ ] Inter/Roboto with no `-apple-system` fallback ahead of it
