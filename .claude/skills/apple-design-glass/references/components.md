# Component Recipes

Complete, copy-pasteable components that wire the tokens, glass materials, and motion physics into shippable parts. Every competing skill stops at principles; this file gives working code. All of it assumes `tokens.css` is imported. Tailwind users: the `.glass` utility and token-backed utilities from `assets/tailwind.css` are noted where they shorten the markup.

Guiding discipline throughout: **transform/opacity only, springs for anything interactive, respond on pointer-down, under 300ms for UI, honor `prefers-reduced-motion`.**

---

## 1. Buttons — filled, tinted, and glass

```css
.btn {
  font: inherit; font-weight: var(--weight-semibold);
  border: none; cursor: pointer;
  padding: var(--space-4) var(--space-6);
  border-radius: var(--radius-capsule);       /* Apple buttons are capsules */
  transition: transform var(--duration-instant) var(--ease-out),
              filter var(--duration-instant) var(--ease-out);
}
.btn:active { transform: scale(0.97); }         /* press physics — never scale(0) */
.btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }

.btn-filled { background: var(--accent); color: #fff; }
.btn-filled:active { filter: brightness(0.92); }

.btn-tinted { background: color-mix(in srgb, var(--accent) 15%, transparent);
              color: var(--accent); }

.btn-glass { color: var(--label); } /* add class="btn btn-glass glass" */
```

Feedback fires on `:active` (pointer-down), not on click. Keep the press subtle — `scale(0.97)` and a slight brightness dip is the whole effect.

---

## 2. Glass navigation bar that collapses on scroll

Apple chrome floats over content as translucent glass and *shrinks/settles* as you scroll down — content dissolves under it via a scroll-edge fade, never a hard divider (see `liquid-glass.md`).

```html
<header class="nav glass" id="nav">
  <span class="nav-title">Library</span>
  <nav class="nav-actions"><button class="btn btn-tinted">Edit</button></nav>
</header>
```

```css
.nav {
  position: sticky; top: 0; z-index: 100;
  display: flex; align-items: center; justify-content: space-between;
  padding: var(--space-4) var(--space-6);
  border-radius: 0 0 var(--radius-lg) var(--radius-lg);
  transition: padding var(--duration-base) var(--ease-out);
}
.nav-title { font-weight: var(--weight-bold); letter-spacing: var(--tracking-snug);
             font-size: var(--text-title-2);
             transition: font-size var(--duration-base) var(--ease-out); }
.nav.condensed { padding-block: var(--space-3); }
.nav.condensed .nav-title { font-size: var(--text-headline); }
```

```js
// Condense on scroll — the large-title → inline-title move.
const nav = document.getElementById("nav");
addEventListener("scroll", () => {
  nav.classList.toggle("condensed", scrollY > 40);
}, { passive: true });
```

Tailwind: `class="nav glass"` where `.nav` holds only layout; use `sticky top-0 z-[100] flex items-center justify-between px-6 py-4` utilities and keep `.glass` as the material.

---

## 3. Segmented control with a sliding indicator

The iOS segmented control: a pill indicator that *springs* between options and inherits the Apple feel. Uses Motion's `layoutId` for the shared indicator (zero geometry math).

```jsx
import { motion } from "motion/react";
import { useState } from "react";

const OPTIONS = ["Day", "Week", "Month"];
export function Segmented() {
  const [active, setActive] = useState(0);
  return (
    <div style={{ display: "flex", gap: 2, padding: 2,
                  background: "var(--fill-3)", borderRadius: "var(--radius-md)" }}>
      {OPTIONS.map((label, i) => (
        <button key={label} onClick={() => setActive(i)}
          style={{ position: "relative", flex: 1, border: "none", background: "none",
                   padding: "6px 14px", cursor: "pointer",
                   fontWeight: "var(--weight-medium)",
                   color: active === i ? "var(--label)" : "var(--label-secondary)" }}>
          {active === i && (
            <motion.span layoutId="seg" transition={{ type: "spring", bounce: 0.15, visualDuration: 0.3 }}
              style={{ position: "absolute", inset: 0, background: "var(--bg-tertiary)",
                       borderRadius: "calc(var(--radius-md) - 2px)", boxShadow: "var(--shadow-1)" }} />
          )}
          <span style={{ position: "relative", zIndex: 1 }}>{label}</span>
        </button>
      ))}
    </div>
  );
}
```

The indicator springs (`bounce: 0.15`) rather than slides linearly — that tiny overshoot is the Apple tell. Text color crossfades as the pill passes under it.

---

## 4. Bottom sheet with full gesture physics (the hard one)

A Vaul-style draggable sheet: 1:1 drag tracking, rubber-band at the top, velocity handoff on release, and momentum projection deciding snap open/closed. This is the flagship interaction — it exercises most of `motion-physics.md`. Vanilla JS + Pointer Events + Motion for the spring, so it works anywhere.

```html
<div class="scrim" id="scrim" hidden></div>
<div class="sheet glass" id="sheet" role="dialog" aria-modal="true">
  <div class="sheet-grabber"></div>
  <div class="sheet-body"><!-- content --></div>
</div>
```

```css
.sheet {
  position: fixed; left: 0; right: 0; bottom: 0; z-index: 200;
  max-height: 92vh; border-radius: var(--radius-2xl) var(--radius-2xl) 0 0;
  transform: translateY(100%);
  touch-action: none;                 /* we handle the gesture ourselves */
}
.sheet-grabber { width: 36px; height: 5px; border-radius: 999px;
  background: var(--label-tertiary); margin: var(--space-3) auto; }
.scrim { position: fixed; inset: 0; z-index: 199; background: rgba(0,0,0,0.4); }
```

```js
import { animate } from "motion";
const sheet = document.getElementById("sheet");
const scrim = document.getElementById("scrim");
const spring = { type: "spring", bounce: 0.2, visualDuration: 0.35 }; // 0.8 / 0.3-ish

let height = 0, startY = 0, currentY = 0, samples = [];
const rubber = (o, dim, c = 0.55) => (o * dim * c) / (dim + c * Math.abs(o));
const project = (v, d = 0.998) => (v / 1000) * d / (1 - d);
const setY = (y) => sheet.style.transform = `translateY(${y}px)`;

export function openSheet() {
  scrim.hidden = false; height = sheet.offsetHeight; currentY = 0;
  animate(sheet, { transform: ["translateY(100%)", "translateY(0px)"] }, spring);
  animate(scrim, { opacity: [0, 1] }, { duration: 0.3 });
}
function close() {
  animate(sheet, { transform: `translateY(${height}px)` }, spring)
    .finished.then(() => (scrim.hidden = true));
  animate(scrim, { opacity: 0 }, { duration: 0.25 });
}

sheet.addEventListener("pointerdown", (e) => {
  sheet.setPointerCapture(e.pointerId);
  startY = e.clientY; samples = [{ y: 0, t: e.timeStamp }];
  sheet.style.transition = "none";
});
sheet.addEventListener("pointermove", (e) => {
  if (!sheet.hasPointerCapture(e.pointerId)) return;
  let dy = e.clientY - startY;
  if (dy < 0) dy = -rubber(-dy, height);   // resist dragging up past the top
  currentY = dy; setY(dy);
  samples.push({ y: dy, t: e.timeStamp });
  if (samples.length > 5) samples.shift();
});
sheet.addEventListener("pointerup", (e) => {
  sheet.releasePointerCapture(e.pointerId);
  const a = samples[0], b = samples[samples.length - 1];
  const v = (b.y - a.y) / ((b.t - a.t) / 1000);          // release velocity px/s
  const landing = currentY + project(v);                  // momentum projection
  if (landing > height * 0.5 || v > 800) close();         // flick or past halfway
  else animate(sheet, { transform: "translateY(0px)" },   // settle back, w/ velocity
               { type: "spring", bounce: 0.2, visualDuration: 0.35, velocity: v });
});
```

Why it feels right: the drag is 1:1, the top edge rubber-bands instead of hard-stopping, a fast flick dismisses even from a short drag (velocity threshold), and the snap decision uses the *projected* landing, not the raw release point — then the settle spring is seeded with the release velocity so there's no seam. Under `prefers-reduced-motion`, replace the open/close with a short opacity fade and skip the drag entirely.

---

## 5. Toast / notification (Sonner-style)

Stacked toasts that spring in from the edge, scale-stack behind each other, and swipe to dismiss with velocity.

```jsx
import { AnimatePresence, motion } from "motion/react";

function Toast({ children, onDismiss }) {
  return (
    <motion.div
      className="glass"
      initial={{ opacity: 0, y: 16, scale: 0.96 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, scale: 0.96, transition: { duration: 0.2 } }}
      transition={{ type: "spring", bounce: 0.2, visualDuration: 0.3 }}
      drag="x" dragConstraints={{ left: 0, right: 0 }} dragElastic={0.6}
      onDragEnd={(e, info) => { if (Math.abs(info.velocity.x) > 400) onDismiss(); }}
      style={{ padding: "var(--space-4) var(--space-5)", borderRadius: "var(--radius-lg)",
               color: "var(--label)" }}
    >{children}</motion.div>
  );
}
```

Enter is a soft spring; exit is a quick fade (asymmetric — arrivals settle, departures leave). A fast horizontal flick dismisses regardless of distance.

---

## 6. Origin-aware popover / context menu

Menus should grow *from* the element that opened them (spatial consistency), not fade in centered. Anchor `transform-origin` to the trigger's side.

```css
.popover {
  position: absolute;
  background: var(--bg-tertiary); border-radius: var(--radius-md);
  box-shadow: var(--shadow-3); padding: var(--space-2);
  transform-origin: top center;              /* grows from the trigger edge */
}
@starting-style { .popover[open] { opacity: 0; transform: scale(0.94); } }
.popover[open] { opacity: 1; transform: scale(1);
  transition: opacity var(--duration-fast) var(--ease-out),
              transform var(--duration-fast) var(--ease-out); }
```

`@starting-style` gives you enter animation for popovers/`<dialog>` with zero JS. Set `transform-origin` to match where the menu is anchored (`top left` for a menu dropping from a top-left button, etc.) so it visibly emanates from its source. Modals are the exception — they scale from center.

---

## 7. Scroll-reveal (restrained)

Content rises and fades once as it enters — subtle, not a wall of animation. GSAP version (also see `gsap.md`):

```js
gsap.utils.toArray(".reveal").forEach((el) => {
  gsap.from(el, { autoAlpha: 0, y: 30, duration: 0.7, ease: "apple-out",
    scrollTrigger: { trigger: el, start: "top 85%", once: true } });
});
```

Reveal each element **once** (`once: true`) — re-animating on every scroll-by is the mark of an overdone site. Stagger groups by 60–80ms max.

---

## Component checklist

- [ ] Interactive parts use springs, not linear transitions
- [ ] Press feedback on pointer-down (`scale(0.97)`), never `scale(0)`
- [ ] Enter/exit asymmetric; menus grow from their source
- [ ] Gestures: 1:1 tracking, rubber-band edges, velocity handoff, momentum snap
- [ ] Glass surfaces have specular highlight + rim + fallbacks
- [ ] All motion transform/opacity only; UI under 300ms
- [ ] `prefers-reduced-motion` path for every animated component
- [ ] Focus-visible outlines; touch targets ≥ 44px
