# Motion (motion.dev), Apple-tuned

Motion is the go-to for **interactive, interruptible, per-component** motion — the gesture-driven springs at the core of the Apple feel. It runs the same hybrid engine in vanilla JS, React, and Vue. Use it over GSAP for anything the user can grab, drag, or reverse mid-flight. See `gsap.md` for the scroll/shared-element/choreography side.

## The spring, mapped to Apple's vocabulary

Motion's spring takes designer-friendly params that map straight onto `motion-physics.md`:

- **`visualDuration`** (seconds) = *response* — how long it visually takes to reach target.
- **`bounce`** (0–1) = *overshoot* — `0` critically damped, `0.3` lively. (Setting `stiffness`/`damping`/`mass` directly overrides `bounce`; only do that for advanced/visualiser cases.)

```js
import { animate } from "motion";

// Apple's ship values as Motion configs:
const move   = { type: "spring", bounce: 0,    visualDuration: 0.4 }; // reposition (1.0/0.4)
const rotate = { type: "spring", bounce: 0.2,  visualDuration: 0.4 }; // rotation   (0.8/0.4)
const sheet  = { type: "spring", bounce: 0.2,  visualDuration: 0.3 }; // drawer     (0.8/0.3)

animate("#pip", { x: 320, y: 40 }, move);
```

**Default to `bounce: 0`** for UI. Add bounce only after a gesture carried momentum, and keep it ≤0.25 — subtle. This matches Emil's rule that springs on UI should be barely perceptible.

## Interruptible by default — spring from the live value

Motion springs read the element's *current* value automatically, so calling `animate` again mid-flight retargets smoothly from wherever it is — exactly the interruptibility principle. Don't gate input while animating.

```js
// Fires repeatedly (e.g. on every hover move) — each call springs from the
// current position and velocity, no snap:
function follow(x, y) {
  animate("#tooltip", { x, y }, { type: "spring", bounce: 0, visualDuration: 0.3 });
}
```

For continuously-tracked values (cursor, tilt), use `useSpring` / a spring-backed motion value instead of re-calling `animate`:

```jsx
import { useSpring } from "motion/react";
const x = useSpring(0, { stiffness: 300, damping: 30 }); // tracks toward .set()
// x.set(pointerX) on every move — the spring smooths it, interruptibly.
```

## Drag with real physics — velocity handoff + momentum, handled

In React, `drag` gives you 1:1 tracking, release-velocity handoff, and momentum for free — the whole §3–6 chain of the physics file:

```jsx
import { motion } from "motion/react";

<motion.div
  drag="y"
  dragElastic={0.18}                 // rubber-band past bounds (0 = hard, 1 = loose)
  dragConstraints={{ top: 0, bottom: 480 }}
  dragMomentum                       // continue at release velocity, decelerate
  dragTransition={{ bounceStiffness: 400, bounceDamping: 40 }}
  onDragEnd={(e, info) => {
    // info.velocity.y is the release velocity — project the landing yourself
    // if you want custom snap logic (see motion-physics.md §6).
    if (info.velocity.y > 500 || info.offset.y > 240) dismiss();
  }}
/>
```

`dragElastic` is rubber-banding; `dragMomentum` is momentum projection; `info.velocity` is the velocity handoff. For a full spring-snapped bottom sheet, combine these with an `animate` call to the snap point using `info.velocity.y` as initial velocity.

## Enter / exit — AnimatePresence, asymmetric

Apple entrances and exits aren't mirror-image speeds — things arrive with a soft settle and leave quickly. Never scale from `0` (it looks like a black hole); start at `0.95` + opacity.

```jsx
import { AnimatePresence, motion } from "motion/react";

<AnimatePresence>
  {open && (
    <motion.div
      initial={{ opacity: 0, scale: 0.95, y: 8 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.98, y: 4 }}
      transition={{ type: "spring", bounce: 0, visualDuration: 0.3 }}
      style={{ transformOrigin: "top" }}   // grow from the source edge
    />
  )}
</AnimatePresence>
```

## Layout animations — the easy shared-element

Motion's `layout` prop auto-animates position/size changes (FLIP under the hood) — a lighter alternative to GSAP Flip when the element stays in the React tree:

```jsx
<motion.div layout transition={{ type: "spring", bounce: 0.15, visualDuration: 0.35 }} />
// Add layoutId="x" on two different elements to morph one into the other
// across mount/unmount (tab indicator, expanding card → sheet).
```

`layoutId` is the clean way to do an Apple "expand from source" between two components (e.g. a grid thumbnail and a detail hero) without manual geometry math. Reach for GSAP Flip instead when the element must reparent outside React's control.

## Scroll — for app-level scroll effects

Motion covers scroll-linked motion too (`useScroll` + `useTransform`), good for progress bars, parallax, and sticky reveals inside a React app. For heavy pinned marketing sequences, GSAP ScrollTrigger is still the stronger tool — pick per context.

```jsx
import { useScroll, useTransform, motion } from "motion/react";
const { scrollYProgress } = useScroll();
const y = useTransform(scrollYProgress, [0, 1], [0, -80]);
<motion.div style={{ y }} />
```

## Performance notes specific to Motion

- Animate `transform`/`opacity`. For elements under heavy load, prefer full transform strings (`transform: "translateX(100px)"`) — animating the `x`/`y` shortcuts is convenient but not always hardware-accelerated the same way.
- Motion respects `prefers-reduced-motion` if you gate springs behind `useReducedMotion()`; swap springs for short opacity fades there rather than killing feedback entirely.
- Keep one spring config object per interaction type (reuse `move`/`sheet` above) so timing stays consistent across the app.

## When to prefer Motion over GSAP

- The thing is **draggable / throwable / reversible mid-gesture** → Motion drag + spring.
- You're in **React** and want layout or presence transitions with minimal code → `layout`, `layoutId`, `AnimatePresence`.
- Per-component micro-interactions (hover, press, toggle) → `animate` / `whileHover` / `whileTap`.

Everything scroll-pinned, per-line text reveal, or reparenting → hand off to `gsap.md`.
