# GSAP, Apple-tuned

GSAP is the missing library in every competing skill. Reach for it over Motion when you need **choreographed, scroll-driven, or shared-element** motion: pinned scroll sequences, layout/FLIP transitions, headline reveals, and precise timelines. For gesture-driven, interruptible, per-component springs, Motion is usually simpler (see `motion-dev.md`) — this file marks which tool wins where.

GSAP v3 is free including all plugins (SplitText, ScrollTrigger, Flip, Draggable, InertiaPlugin, MorphSVG) as of 2024. Register plugins once at module scope.

## Setup

```js
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { Flip } from "gsap/Flip";
import { Draggable } from "gsap/Draggable";
import { InertiaPlugin } from "gsap/InertiaPlugin";
import { SplitText } from "gsap/SplitText";
import { CustomEase } from "gsap/CustomEase";
gsap.registerPlugin(ScrollTrigger, Flip, Draggable, InertiaPlugin, SplitText, CustomEase);
```

## Apple easing as CustomEase (the exact curves)

GSAP's built-in `power`/`back` eases are close, but Apple's signature curves are these béziers — define them once and reference by name everywhere. This is how you get the *feel* right instead of "generic smooth":

```js
CustomEase.create("apple-out",    "0.23, 1, 0.32, 1");     // default exit-of-motion
CustomEase.create("apple-in-out", "0.77, 0, 0.175, 1");    // symmetric moves
CustomEase.create("ios",          "0.32, 0.72, 0, 1");     // sheets/drawers

gsap.to(".card", { y: 0, autoAlpha: 1, duration: 0.5, ease: "apple-out" });
```

**Discipline (same as Motion):** never `ease: "power2.in"` on UI entrances — starting slow reads as lag. Use `apple-out` for things arriving, `apple-in-out` for things repositioning. Keep UI transitions under 300ms; reserve longer for sheets/hero moments. For overshoot, `back.out(1.4–1.7)` ≈ a subtle spring bounce — keep the overshoot small.

## Timelines — sequence, don't stack delays

Prefer a timeline over chained `delay:` values; it stays editable and reversible (reversibility = interruptibility, the Apple principle).

```js
const tl = gsap.timeline({ defaults: { duration: 0.5, ease: "apple-out" } });
tl.from(".title",   { y: 40, autoAlpha: 0 })
  .from(".subtitle",{ y: 24, autoAlpha: 0 }, "-=0.35")   // overlap for flow
  .from(".cta",     { y: 16, autoAlpha: 0 }, "-=0.3");
// tl.reverse() to play it backwards — mirrored path, Apple-style.
```

Use `autoAlpha` (opacity + visibility) rather than raw `opacity` so hidden elements are also removed from the a11y tree and hit-testing.

## Flip — shared-element / layout transitions (GSAP's superpower)

This is the web-native version of Apple's "expand from source" motion (a thumbnail growing into a detail view, a card morphing into a sheet). No other skill teaches it. Pattern: **capture state → mutate the DOM → animate the delta.**

```js
const state = Flip.getState(".hero-img");   // 1. record current geometry
detailView.appendChild(heroImg);            // 2. move/reparent/resize freely
Flip.from(state, {                          // 3. GSAP animates the difference
  duration: 0.5,
  ease: "apple-in-out",
  absolute: true,                           // avoids layout jor during the flip
  scale: true,                              // scale instead of width/height (GPU)
});
```

Because Flip animates `transform` only, it stays smooth. This is the correct tool for gallery→lightbox, list→detail, and grid reflow. It also makes reordering (filtering a grid) feel physical:

```js
const state = Flip.getState(".grid-item");
// reorder / filter the DOM ...
Flip.from(state, { duration: 0.5, ease: "apple-out", stagger: 0.03, absolute: true });
```

## ScrollTrigger — scroll-driven & pinned sequences

Apple's product pages (the canonical "Apple aesthetic on the web") are built on pinned, scroll-scrubbed sequences. `scrub` ties progress to scroll position; `pin` holds the section while the sequence plays.

```js
const tl = gsap.timeline({
  scrollTrigger: {
    trigger: ".showcase",
    start: "top top",
    end: "+=2400",       // scroll distance the pinned scene lasts
    scrub: 1,            // 1 = smoothed catch-up (feels premium vs scrub:true)
    pin: true,
  },
});
tl.to(".device", { scale: 1.15, ease: "none" })
  .from(".feature-1", { autoAlpha: 0, y: 40 }, "<")
  .to(".device", { rotateY: 12, ease: "none" });
```

- Use `scrub: 1` (a number) not `true` for a subtle inertial smoothing that feels Apple, not mechanical.
- Reveal-on-scroll (the restrained version, not a wall of animation):
  ```js
  gsap.utils.toArray(".reveal").forEach((el) => {
    gsap.from(el, {
      autoAlpha: 0, y: 30, duration: 0.7, ease: "apple-out",
      scrollTrigger: { trigger: el, start: "top 85%", once: true },
    });
  });
  ```
- **Call `ScrollTrigger.refresh()` after layout changes** (font load, images, route change) or triggers desync.

## SplitText — headline reveals

Apple's marquee headlines animate per-line or per-word with a soft rise. SplitText makes this one call:

```js
const split = SplitText.create(".headline", { type: "lines,words", mask: "lines" });
gsap.from(split.lines, {
  yPercent: 100, autoAlpha: 0, duration: 0.8, ease: "apple-out", stagger: 0.08,
});
```

`mask: "lines"` clips each line so words rise from behind an invisible edge — the clean Apple reveal. Keep stagger 60–90ms; more feels slow. Split *after* fonts load to avoid reflow.

## Draggable + InertiaPlugin — momentum & snapping

This is GSAP's answer to gesture physics: real velocity handoff and momentum projection (§5–6 of `motion-physics.md`) handled for you.

```js
Draggable.create(".sheet", {
  type: "y",
  inertia: true,                       // throw momentum after release (InertiaPlugin)
  edgeResistance: 0.85,                // rubber-band at bounds (higher = firmer)
  bounds: { minY: 0, maxY: 480 },
  snap: { y: (v) => (v > 240 ? 480 : 0) }, // projected landing decides open/closed
  onThrowUpdate() { /* live value available for interruptible logic */ },
});
```

`inertia: true` continues at the release velocity and decelerates naturally — the "flick lands where it was going" behavior — and `snap` receives the *projected* value, so you snap based on momentum, not raw position. `edgeResistance` gives you rubber-banding for free.

## quickTo — high-frequency followers (cursor, tilt, parallax)

For values that update every mousemove, don't create tweens per event — reuse one with `quickTo` (the Apple "magnetic"/parallax feel, GPU-friendly):

```js
const xTo = gsap.quickTo(".cursor", "x", { duration: 0.4, ease: "apple-out" });
const yTo = gsap.quickTo(".cursor", "y", { duration: 0.4, ease: "apple-out" });
addEventListener("pointermove", (e) => { xTo(e.clientX); yTo(e.clientY); });
```

## React — `useGSAP` (scoped, auto-cleanup)

Always scope to a ref and let `useGSAP` revert on unmount; wrap event-handler animations in `contextSafe`.

```jsx
import { useGSAP } from "@gsap/react";
gsap.registerPlugin(useGSAP);

function Hero() {
  const scope = useRef(null);
  const { contextSafe } = useGSAP(() => {
    gsap.from(".hero-title", { y: 50, autoAlpha: 0, duration: 0.8, ease: "apple-out" });
  }, { scope });

  const onClick = contextSafe(() => {
    gsap.to(".cta", { scale: 1.06, duration: 0.18, yoyo: true, repeat: 1, ease: "apple-out" });
  });
  return <section ref={scope}>…</section>;
}
```

## Motion vs GSAP — which tool when

| Task | Use |
|---|---|
| Gesture-driven, interruptible, per-component springs | **Motion** (`animate`, `useSpring`, drag) |
| Shared-element / layout / grid-reflow transition | **GSAP `Flip`** |
| Pinned, scroll-scrubbed hero sequence | **GSAP `ScrollTrigger`** |
| Per-line/word headline reveal | **GSAP `SplitText`** |
| Simple enter/exit, layout animation in React | **Motion** (`layout`, `AnimatePresence`) |
| Throwable sheet/carousel with momentum | Either — **Motion drag** or **GSAP `Draggable`+`Inertia`** |
| High-frequency cursor/parallax follower | **GSAP `quickTo`** (or Motion `useSpring`) |

Don't load both libraries for one small job. Pick per surface: a marketing/scroll-heavy page leans GSAP; an app with lots of interactive components leans Motion.

## Performance & discipline

- Animate `transform`/`opacity`/`autoAlpha` — GSAP writes them efficiently, but layout props still thrash.
- `gsap.ticker` is already rAF-synced; don't hand-roll a loop alongside it.
- Kill/scope everything in SPAs (`useGSAP` or `gsap.context().revert()`), or ScrollTriggers leak across routes.
- Wrap in `ScrollTrigger.matchMedia()` / `gsap.matchMedia()` to disable heavy scroll scenes under `prefers-reduced-motion` and on small screens.
