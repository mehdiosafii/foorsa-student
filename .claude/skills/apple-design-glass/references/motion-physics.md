# Motion Physics — the Apple fluid-interface model

This is the heart of the Apple feel, distilled from *Designing Fluid Interfaces* (WWDC 2018). The thesis in one sentence:

> **An interface feels alive when motion starts from the current on-screen value, inherits the user's velocity, projects momentum forward, and can be grabbed and reversed at any instant.**

Everything below serves that sentence. This file is **library-agnostic** — it gives you the physics and the numbers. `motion-dev.md` and `gsap.md` show the same ideas in each library. If you only remember one thing: **use springs, not durations, for anything the user can touch.**

## 1. Springs, described the way designers think

Don't reason about `stiffness`/`mass`/`damping` directly — they're unintuitive. Apple exposes two parameters, and you should too:

- **Response** — how long the spring visually takes to reach its target (in seconds). Smaller = snappier.
- **Damping ratio / bounce** — overshoot. `1.0` damping = *critically damped* = no overshoot. Below `1.0` overshoots and settles (bounce). Above never overshoots but drags.

These map cleanly onto both libraries:

| Concept | Motion (`motion`) | GSAP |
|---|---|---|
| Response (time-to-target) | `visualDuration: 0.4` | ease duration + `CustomEase` / `back` |
| Overshoot | `bounce: 0` (none) → `bounce: 0.3` (lively) | `ease: "back.out(1.4)"` overshoot amount |

### Apple's actual ship values

These are the damping/response pairs Apple uses in shipping iOS interactions. Use them as your defaults — they are *tuned*, not arbitrary:

| Interaction | Damping | Response | Motion equivalent |
|---|---|---|---|
| Move / reposition (e.g. PiP window) | 1.0 | 0.4 | `{ type:"spring", bounce:0, visualDuration:0.4 }` |
| Rotation | 0.8 | 0.4 | `{ type:"spring", bounce:0.2, visualDuration:0.4 }` |
| Drawer / sheet | 0.8 | 0.3 | `{ type:"spring", bounce:0.2, visualDuration:0.3 }` |

**Rule of thumb:** default to **critically damped** (`bounce: 0`, `visualDuration: 0.3–0.4`) for most UI. Only add bounce when the gesture *carried momentum* (a flick, a throw) — bounce on a plain tap looks toy-like. Keep bounce subtle: `0.1–0.25`. Emil's guidance agrees: springs on UI should whisper.

## 2. Interruptibility — the single most important principle

If a user can start a gesture, they must be able to reverse it *mid-flight* without waiting. This is what makes Apple UI feel like a physical object rather than a slideshow of states.

Requirements:
- **Animate from the presentation (live) value**, not from a logical "start." Read the element's *current* transform and spring from there.
- **Never lock input during a transition.** No `pointer-events: none` gates, no "wait for the animation to finish."
- **Avoid CSS transitions/keyframes for gesture-driven motion.** They can't be interrupted cleanly — they snap or fight you. Use a spring animation (Motion) or a tween you can `kill`/retarget (GSAP `quickTo`) instead.
- **Decompose 2D motion into independent X and Y springs.** A single 2D spring can't respond to a horizontal flick during a vertical settle. Two independent springs can.

```js
// The pattern (library-neutral): on every new target, spring from wherever
// the element visually is right now — not from a stored origin.
function retarget(el, toY) {
  const currentY = getCurrentTranslateY(el);   // read the LIVE value
  springTo(el, { from: currentY, to: toY, velocity: lastVelocity });
}
```

## 3. Direct manipulation — 1:1 tracking

While a finger/pointer is down, content moves *exactly* with it. No easing, no lag — easing here feels broken.

- Use **Pointer Events** + `setPointerCapture` so you keep receiving moves even if the pointer leaves the element.
- **Respect the grab offset**: the point the user grabbed stays under their finger. Don't snap the element's origin to the cursor.

```js
el.addEventListener("pointerdown", (e) => {
  el.setPointerCapture(e.pointerId);
  const startTop = el.getBoundingClientRect().top;
  const grabOffset = e.clientY - startTop;   // where within the element they grabbed
  // track {y, t} samples for velocity (see §5)
  el.dataset.grab = grabOffset;
});
```

## 4. Respond on pointer-down — kill latency

Feedback begins on **touch-down**, not release. A button darkens/scales the instant it's pressed; a row highlights on contact. Remove debounces and `transition-delay` on interactive feedback. Continuous feedback throughout the gesture, never only at the end.

```css
.button { transition: transform 100ms var(--ease-out); }
.button:active { transform: scale(0.97); }   /* never scale(0); 0.95–0.97 */
```

## 5. Velocity handoff — the seam between drag and animation

When the finger lifts, the animation must continue *at the finger's exact speed*. A drag that ends at 2000px/s and then eases from zero feels like hitting a wall.

Sample position + timestamp during the drag, compute velocity at release, and pass it as the spring's **initial velocity**:

```js
// keep a short history of {y, t}; velocity = recent Δy / Δt (px per second)
function releaseVelocity(samples) {
  const a = samples[samples.length - 2], b = samples[samples.length - 1];
  return (b.y - a.y) / ((b.t - a.t) / 1000);   // px/s
}
```

For libraries whose spring wants a *relative* velocity (fraction of the remaining distance per second), convert:

```js
const relativeVelocity = gestureVelocity / (targetValue - currentValue);
```

Both Motion (`velocity` option / drag momentum) and GSAP (`InertiaPlugin` `velocity`) accept a release velocity — always feed it.

## 6. Momentum projection — animate to where the gesture is *going*

A flick should land where the finger *would have* carried the content, not where it happened to lift. Use Apple's projection function (from *Designing Fluid Interfaces*) to compute the resting point:

```js
// Apple's actual projection — NOT the textbook v²/(2·decel), which overshoots.
function project(initialVelocity /* px/s */, decelerationRate = 0.998) {
  return (initialVelocity / 1000) * decelerationRate / (1 - decelerationRate);
}
const landing = currentPosition + project(releaseVelocity(samples));
```

- `decelerationRate ≈ 0.998` for normal scroll-like momentum; `0.99` for snappier, shorter throws.
- Use the projected landing to decide snapping: if `landing` passes the halfway point (or a threshold), snap open; else snap closed — then spring there *with the release velocity*. This is exactly how Vaul (sheets) and Embla (carousels) feel right.

## 7. Rubber-banding — soft boundaries

Content never hard-stops at an edge; it resists progressively and pulls back. Apply increasing damping past the boundary:

```js
// c ≈ 0.55; dim = the dimension along the axis (e.g. sheet height / viewport).
function rubberBand(overshoot, dim, c = 0.55) {
  return (overshoot * dim * c) / (dim + c * Math.abs(overshoot));
}
// while dragging past the top: y = boundary + rubberBand(rawY - boundary, height);
```

The further past the edge, the more it resists — you can pull, but it fights back, and it springs home on release. A hard clamp (`Math.min/max`) feels cheap; rubber-banding feels physical.

## 8. Gesture details — the "feel" checklist

- **Tap:** highlight on touch-down, commit on touch-up. If the finger moves off before release, cancel.
- **Drag threshold:** require ~10px of movement before committing to a drag direction, so taps aren't misread as drags.
- **Detect gestures in parallel** from the first move (is this a tap? a horizontal swipe? a vertical drag?) and disambiguate as evidence arrives. Don't block on a timeout.
- **Velocity-based dismissal:** a fast flick dismisses even if the drag distance was short — `Math.abs(velocity) > ~0.11 px/ms` is a good threshold for swipe-to-dismiss.

## 9. Frame-level smoothness — performance is a feature

Janky motion breaks the illusion no matter how good the physics.

- **Animate only `transform` and `opacity`** — they're compositor-only (no layout/paint). Never animate `top`/`left`/`width`/`height` in motion.
- In **Motion**, use full transform strings for hardware acceleration where it matters: `transform: "translateX(100px)"` composites; note that animating the shorthand `x`/`y` props is convenient but not always GPU-accelerated under load.
- Use `will-change: transform` *just before* an imminent animation, and remove it after — it's a hint, not a set-and-forget.
- Keep per-frame positional change below the perception threshold; drive continuous gestures with `requestAnimationFrame` (or the library's frame loop), synced to display refresh.
- CSS/WAAPI animations keep running on the compositor even when the main thread is busy; prefer them for fire-and-forget entrance motion, and reserve JS springs for interactive/interruptible motion.

## 10. Spatial consistency & telegraphing

- **Enter and exit along the same path.** If a menu grows from a button, it shrinks back into that button. Anchor transforms to the source element (`transform-origin`), and mirror the easing on reverse (`--ease-out` in ↔ its inverse out).
- **Hint in the direction of the gesture.** Intermediate frames should point at the outcome — a sheet that's being pulled up should already be moving up as you grab it, not sitting still until you cross a threshold.

## Reduced motion — gentler, not gone

`prefers-reduced-motion: reduce` doesn't mean *no* feedback — it means no large/springy/parallax motion. Replace slides and springs with short opacity crossfades; drop overshoot and elastic behavior; keep the instant tap feedback (opacity/color) that communicates cause and effect. The token layer already collapses durations globally; override per-component where a crossfade reads better than a hard cut.

## Quick reference

| Need | Technique | Value |
|---|---|---|
| Default UI spring | critically damped | `bounce:0`, `visualDuration:0.3–0.4` |
| Momentum spring | under-damped | `bounce:0.15–0.25` |
| Reposition | Apple ship value | damping 1.0 / response 0.4 |
| Sheet/drawer | Apple ship value | damping 0.8 / response 0.3 |
| Velocity → spring | pass release velocity | `gestureVelocity/(target−current)` |
| Flick landing | project momentum | `current + (v/1000)·d/(1−d)`, d≈0.998 |
| Interrupt cleanly | spring from live value | read current transform |
| Soft edge | rubber-band | `(o·dim·0.55)/(dim+0.55·|o|)` |
| Press feedback | on pointer-down | `scale(0.97)`, 100ms, `--ease-out` |
| Reversible transition | mirror easing + origin | inverse curve, anchored origin |
| Smoothness | transform/opacity only | `will-change` just-in-time |
