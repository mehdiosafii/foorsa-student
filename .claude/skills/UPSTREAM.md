# Vendored design skills

These skills are not written by this project. They are vendored verbatim
from four upstream repositories:

| Source | Licence | Pinned commit |
| --- | --- | --- |
| <https://github.com/emilkowalski/skills> (Emil Kowalski) | MIT, `LICENSE.emilkowalski` | `.upstream-sha.emilkowalski` |
| <https://github.com/pbakaus/impeccable> (Paul Bakaus) | Apache 2.0, `LICENSE.impeccable`, `NOTICE.impeccable.md` | `.upstream-sha.impeccable` |
| <https://github.com/leonxlnx/taste-skill> (Leonxlnx) | MIT, `LICENSE.taste-skill` | `.upstream-sha.taste-skill` |
| <https://github.com/bowen31337/apple-design> (bowen31337) | **none published** | `.upstream-sha.bowen31337-apple-design` |

bowen31337/apple-design ships no licence file, which by default means all
rights reserved. It is vendored here for private use at the owner's request;
do not redistribute it, and replace it if the author publishes terms that
forbid this.

## Why vendored instead of `npx skills add`

Upstream's install path is `npx skills@latest add <repo>`, which resolves
through `skills.sh`. This repository is developed largely from ephemeral containers
(Claude Code on the web, CI), where the container is rebuilt on every session
and outbound egress is filtered — `skills.sh` is not reachable from there.
Committing the files means the skills are present the moment the repository is
cloned, with no install step and no network dependency, and the exact revision
in use is reviewable in git history.

Each skill lives under its frontmatter `name`, which is the name it is invoked
by. The one exception is bowen31337/apple-design, which is also called
`apple-design` upstream: it is installed as `apple-design-glass` so it does not
overwrite Emil's.

## What is here

### emilkowalski/skills

| Skill | Invoked | Purpose |
| --- | --- | --- |
| `emil-design-eng` | automatic | Main skill: UI polish, component design, animation decision framework. |
| `animate` | automatic | Builds a web animation from scratch — curve, duration, properties, interruption, exit. |
| `animate-expo` | automatic | Same bar for React Native/Expo. |
| `apple-design` | automatic | Apple's interface and motion principles, translated for the web. |
| `mobile-native` | automatic | Makes a web app feel native on a phone: tap highlight, 100vh, input zoom, safe areas. |
| `write-swift` | automatic | Modern Swift. |
| `find-animation-opportunities` | automatic | Read-only: finds UI that should animate, and rejects what should not. |
| `improve-animations` | automatic | Read-only: audits motion across the codebase, emits prioritised plans. |
| `animation-vocabulary` | automatic | Reverse glossary — describe a motion effect, get its exact name. |
| `ask-sonner` | automatic | Sonner toast library reference. |
| `review-animations` | `/review-animations` | Strict review of animation code. Approval is earned. |
| `pick-ui-library` | `/pick-ui-library` | Curated library recommendations instead of hand-rolled components. |
| `prototype` | `/prototype` | Builds several variants of a UI piece behind a visual switcher. |

The last three carry `disable-model-invocation: true` upstream: they only run
when you invoke them by name. That is deliberate and has been left as-is.

### pbakaus/impeccable

| Skill | Invoked | Purpose |
| --- | --- | --- |
| `impeccable` | automatic, or `/impeccable <command>` | One skill with sub-commands: `shape`, `audit`, `critique`, `polish`, `typeset`, `layout`, `colorize`, `quieter`, `bolder`, `harden`, `optimize`, `adapt` and more; playbooks in `reference/`. |

Its setup step runs `scripts/impeccable context`, a launcher that downloads a
platform binary on first use. That needs network access to GitHub releases; in
a container that cannot reach it, the reference playbooks still work read
directly.

### leonxlnx/taste-skill

| Skill | Purpose |
| --- | --- |
| `design-taste-frontend` | Main skill: anti-template frontend design, audit-first on redesigns. |
| `design-taste-frontend-v1` | The original v1, kept upstream for backward compatibility. |
| `redesign-existing-projects` | Audits an existing UI for generic patterns and upgrades it. |
| `high-end-visual-design` | Agency-grade fonts, spacing, shadows, cards and motion. |
| `minimalist-ui` | Editorial minimalism: warm monochrome, flat bento grids. |
| `industrial-brutalist-ui` | Swiss-print / terminal brutalism for data-heavy UIs. |
| `gpt-taste` | GSAP-heavy, AIDA-structured landing pages. |
| `stitch-design-taste` | Writes a `DESIGN.md` design system for Google Stitch. |
| `full-output-enforcement` | Bans placeholder and truncated code output. |
| `image-to-code` | Generates design images, then implements them. Needs an image model. |
| `imagegen-frontend-web` / `imagegen-frontend-mobile` | Image generation only, no code. Needs an image model. |
| `brandkit` | Brand-guideline boards as images. Needs an image model. |

### bowen31337/apple-design

| Skill | Purpose |
| --- | --- |
| `apple-design-glass` | Apple look in CSS: Liquid Glass materials, spring physics in Motion and GSAP, SF typography, a token layer (`assets/`) and copy-paste components. |

## Refreshing from upstream

The canonical copy lives in `mehdiosafii/hanlu`, whose
`scripts/sync-design-skills.sh` re-pulls all four upstreams. Refresh there,
then copy the skill folders, `LICENSE.*`, `NOTICE.*` and `.upstream-sha.*`
across. Do not edit the vendored files here: project rules belong in
`CLAUDE.md` or in this repository's own skills.
