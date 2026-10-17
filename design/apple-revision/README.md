# One Home — an Apple-style revision of Foorsa Student

A proposal for every interface of the student app, written against the
vendored `apple-design` and `apple-design-glass` skills
(`.claude/skills/`). It removes the footer menu and makes Home the only
root: the app leads with the one next thing, and every interface opens from
Home and comes back to it.

**See it:** open [`prototype.html`](prototype.html) in a browser. On a phone it
fills the screen; on a computer it shows a phone with controls beside it
(phase, appearance and an index of every interface). In the phone itself,
Profile › Prototype has the same controls. The data is sample data.

---

## 1. What changes, in one paragraph

The six-tab dock goes. Home becomes a single scrolling page in a fixed order:
where you are (a seven-step rail), the one next thing, what to pay, your file,
your study, and China. Everything else is one tap away and leaves Home in one
of three ways, each with its own way back:

| Kind | For | Enters | Back |
| --- | --- | --- | --- |
| **Push** | Reading and lists: My journey, Documents, All files, Payments, Universities, Visa, Flight, Checklist, Calendar, My progress, Phrases, Kitchen, Community | Slides in from the right; Home slides a third left and dims | Glass back button, or a swipe from the left edge (1:1, decided by where the swipe was going) |
| **Sheet** | A task: Contact, Profile, Pay one line, Add the receipt, Send a paper, eSIM, A faster visa, Money, Prayer times, Papers, Halal food, Your city, Recipe | Rises from the bottom; Home recedes behind it | Close button, or drag it down (a flick is enough) |
| **Cover** | A place that needs the whole screen: CSCA, HSK, Show the driver, a phrase shown large, Discover China, the admission letter, document preview | Grows out of the tile that opened it | Chevron or close at top left; it folds back into its tile |

## 2. Why — what the current interface does today

Read from the portal's code before this proposal:

- **Navigation.** Six tabs share the bottom of a phone (47–53 px each under
  375 px wide, where "Documents" becomes "Docs"). Badges sit in the tab
  corner. The "‹ Home" link scrolls away with the page and opens Home as a new
  screen instead of going back; folder pages show two back links.
- **Reachability.** Kitchen and Community are reached only from tiles inside
  Tools. Billing lives both in the Pay tab and inside Profile.
- **Materials.** About ten glass recipes and nine effects per card, stacked
  over a 22-stop folded backdrop that sits behind text. On phones the blur is
  switched off, so cards read as tinted plastic with heavy shadows.
- **Colour and type.** Seven navies, an accent that turns from indigo to teal
  in dark mode, two greens for "done", about 18 font sizes, nine corner
  radii, three different left edges.
- **Motion.** Springs drive the dock pill and some pages, but sheets have no
  drag-to-dismiss and no exit, and every card replays a 420 ms rise on every
  visit.
- **Words.** "Pay", "Billing" and "Payments" name one screen; Pay prints
  "RMB" where Universities prints "CNY"; the study card says "while you wait"
  to a student already in China.

## 3. What stays exactly as decided

These rules shaped the current app and the proposal keeps every one:

- Home leads with **one** next thing, chosen by the same precedence (pause,
  travel day, admission letter, dated events, what the student can do, then
  routine).
- **To pay stays on Home**: one row per line, in its own currency, never
  summed.
- A receipt reads **"Being checked"**, never "Paid", until Foorsa confirms it.
- Status is always a **word**; colour only repeats it.
- Papers are asked for **slowest first**; private papers can be sent but never
  seen, and they show as status lines only.
- **CSCA by Foorsa** only for bachelor and Chinese-language students, **HSK by
  Foorsa** for everyone; both open inside the app and resume where they were
  left.
- In China nothing needs Google, YouTube or WhatsApp: Amap for maps, WeChat
  first for contact, no video frames, ingredients instead.
- The spring physics (damping and response, velocity hand-off, momentum
  projection, rubber-banding) — now used everywhere, not only on the dock.

## 4. Where the dock's jobs went

| Dock tab | In One Home |
| --- | --- |
| Home | Home is the app. |
| Documents | "Your file › Documents", with its state as a word: "1 to redo", "All set". |
| Pay | "To pay" on Home, every unpaid line, plus "All payments". |
| CSCA, HSK | Two Study tiles on Home with their progress. They open full screen — with no dock, the lessons get the whole phone — and are never torn down. |
| Contact | A message button beside the avatar at the top of Home, and "Message" on the adviser row at its end. |
| Tools (in China) | On Home: **I'm OK** first, then a grid of the six tools that work without a VPN. |

The red badges become words on the rows they belong to.

## 5. Home, top to bottom

**Before departure** (the prototype shows step 4, admitted by two universities):

1. A small line with both clocks: "14:42 in Morocco · 21:42 in China".
2. "Hi, Salma" as the large title; Contact and the avatar (Profile) beside it.
3. The rail: seven segments and "Step 4 of 7 · Admission ›" (opens My journey).
4. The next thing: "Your admission letter has arrived." — one button.
5. **To pay**: one row per unpaid line.
6. **Your file**: Documents, Universities, Payments (Visa, Flight, eSIM appear
   at their steps).
7. **Study**: CSCA by Foorsa and HSK by Foorsa, with "My progress".
8. **Get ready for China**: Discover China, Kitchen, Community, eSIM — a row
   that scrolls sideways.
9. Your adviser, with "Message".

**In China** the same page reorders itself: the next class leads ("Today ·
next class"), then I'm OK, then Tools (Show the driver, Money, Phrases, Prayer
times, Papers, Halal food), then To pay, Your file (Documents, Payments,
Calendar, Arrival steps, Your university), Study and **Life in China** (your
city's weather, Discover China, Kitchen, Community).

## 6. Each interface gets the layout its content needs

| Interface | Layout |
| --- | --- |
| My journey | A vertical timeline that fills to today; only the current step opens, with its one button. |
| Documents | A meter ("8 of 9 ready"), then grouped by what needs you: **Needs you** (with the redo reason, word for word), **Being checked**, **On file** (Accepted folds into one row), **Your details** ("Right?"), and All files. |
| Send a paper | One sheet instead of three steps: the reason, the instructions in French or Arabic, then **Scan** or **Choose a file**. |
| All files | A two-column grid of thumbnails with filters; private papers never listed. |
| Document preview | Native, Quick Look style: black, floating Done, the file name, Save, a page count. |
| Payments | Each unpaid line is a pass: label, a large amount in its currency, due date. Then Being checked and Paid as quiet lists. |
| Pay one line | Transfer first: amount, then Beneficiary, Bank, RIB and Reference with Copy, then "I paid, add the receipt"; card second, with its 7%. A CNY line says the account takes MAD. |
| Universities | Photo-led cards with the facts in two columns (tuition, rooms, CSCA minimum against yours). Choosing is a toggle on each card; a glass bar at the bottom says what will happen ("Join Zhejiang University"). |
| Visa | The day first, as a calendar block ("Tue 14"), who meets you and where; then the embassy steps as a checklist; a faster visa in a sheet. |
| Flight | A boarding pass: airport codes, date, departure, flight; the ticket; the family link; Before you fly. |
| Checklist | Before you fly / Arrival steps: tick-able rows, the next one marked. |
| Calendar | A week strip and the day's agenda, the current class outlined; scan a timetable; reminders as a switch. |
| My progress | Two cards, each a 3×2 grid of figures and the latest results. |
| CSCA, HSK | Full screen, chevron top left; each site keeps its own sections pill at the bottom, where the dock used to be. |
| Show the driver | A white poster in every theme: 请带我去, the university and its address in large Chinese, pinyin and English, "Open in Amap". |
| Phrases | Topic chips and a list; a phrase opens as the same poster. |
| Money | A calculator: CNY in, MAD or TND out, the rate's date underneath. |
| Prayer times | Off until switched on; computed on the phone; the next prayer highlighted. |
| Papers | Passport, visa, residence permit, each with a word ("Valid", "45 days left", "Not on file"). |
| Halal food | 清真 large, what it means, "Halal restaurants near me". |
| Your city | The weather as one large figure and a short forecast, then your university with Directions. |
| Discover China | The 3D voyage as it is, now a full-screen cover with its "Where to?" sheet. |
| Kitchen | Search, cuisine chips, a two-column grid; a recipe opens as a sheet with ingredients in English and Chinese. |
| Community | My destination / Foorsa; a quiet chat with a floating composer. |
| Contact | Your adviser, three actions (WhatsApp or WeChat, Call, Email), your contact in China once assigned, your requests. |
| Profile | Settings-style: personal information, contract, family link; Appearance; password, privacy, about; sign out; delete account last. |
| Sign in | The mark, "Foorsa Student", two fields, one button. |
| Admission letter | Kept as the app's one ceremony. |

## 7. Visual system

One token layer (from `.claude/skills/apple-design-glass/assets/tokens.css`):

- **Ground and surfaces.** Grouped ground `#F2F2F7` / `#000000`; cards and
  rows `#FFFFFF` / `#1C1C1E`. The folded backdrop is removed.
- **Brand.** Foorsa navy `#183250` fills the primary button in light mode; in
  dark mode the primary button is light (`#F2F4F8` with `#0B1220` text). One
  tint for links and icons: `#1F4E8C` / `#8CB6F0`.
- **Status — four colours, always with a word.** To add (tint), Redo and
  "days left" (orange `#A84700` / `#FFA31A`), Being checked (indigo `#3B47B0`
  / `#A5A9FF`), Accepted and Paid (green `#1D7A35` / `#30D158`), Not needed
  (gray).
- **Shape.** One card radius (22 px), capsule buttons, 9 px icon tiles, a
  16 px gutter everywhere.
- **Type.** The system font, as Apple's text styles: Large Title 34/700
  (−0.022 em), Title 2 22/700, Title 3 20/700, Headline 17/600, Body 17,
  Subhead 15, Footnote 13 (+0.01 em), Caption 12. Tight leading on titles,
  looser on small text.
- **Glass only for what floats**: back and close buttons, the choose bar, the
  composer, the toast. Each has a lit top edge, a hairline rim and a soft
  shadow; with Reduce Transparency it becomes solid. Content is never glass.
- **Scroll edges, not bars.** When a page scrolls, its title appears small at
  the top over a soft blur; there is no divider line.

## 8. Motion

Springs are set by damping and response (seconds), as in Apple's tools:

| Motion | Damping / response |
| --- | --- |
| Push in | 1.0 / 0.42 |
| Pop (button or swipe; inherits the swipe's speed) | 1.0 / 0.38 |
| Sheet in / out | 1.0 / 0.40 · 1.0 / 0.36 |
| Sheet settling back after a drag | 0.86 / 0.34, with the finger's speed |
| Cover in / out | 1.0 / 0.46 · 1.0 / 0.40 |
| Segmented control, toast | 0.82 / 0.32 · 0.8 / 0.3 |

- A drag follows the finger 1:1. Release decides by the **projected** landing
  point (deceleration 0.998), not where the finger stopped. Above a sheet's
  top the drag rubber-bands.
- Every motion can be interrupted: a closing screen never blocks the next tap.
- Buttons and tiles press to 0.97 on touch-down; list rows highlight instead.
- Reduce Motion: no slides, no growth, the change is immediate. Nothing replays
  an entrance on every visit.

## 9. The native shell (this repository)

| Today | Proposed |
| --- | --- |
| Splash `#183250` in both themes, then a white or navy loading screen | Splash and loader on Home's ground (`#F2F2F7` light, `#000000` dark), mark centred, the Flicker loader small below it; no dark-to-light flash |
| Offline: gradient, glass card, French title | Plain ground, a Wi-Fi glyph, "No internet connection" with the Arabic line, "We'll reconnect as soon as you're back online", a quiet Try again |
| File preview: Material app bar on `#10192E` | Quick Look style: black, floating Done, title, Save, page count |
| Status-bar strip `#0B1220` until the portal reports a colour | Starts on the Home ground; the portal reports `#F2F2F7` / `#000000` |
| Snackbars in French and English | One language: "Saved to Downloads" (Android) or "Saved to Files › Foorsa Student" (iPhone), "Couldn't open this file", "Press back again to exit" |

## 10. How it could ship

Each phase stands on its own:

1. **Foundation** — tokens, type styles, one radius, glass only for floating
   chrome, flat ground. No change to where anything is.
2. **One Home** — remove the dock; Home in the order above; push, sheet and
   cover transitions; CSCA and HSK full screen.
3. **Interfaces** — one at a time, in the layouts of section 6.
4. **Native shell** — splash, offline, preview and copy, with the next store
   build.

## 11. Open questions for the owner

1. CSCA and HSK were decided "always there in the footer menu". Are two tiles
   near the top of Home, opening full screen and resuming where the student
   stopped, close enough to "always one tap away"?
2. Is a message button beside the avatar enough for Contact, or should Home
   also end with a labelled "Message Foorsa" row (the prototype has both)?
3. One currency word everywhere: CNY or RMB?
4. One name for the money screen: "Payments"?
5. Inside the app the CSCA and HSK sites would move their sections pill to the
   bottom and leave the top-left corner for the close button — a small change
   in each site's in-app skin.
