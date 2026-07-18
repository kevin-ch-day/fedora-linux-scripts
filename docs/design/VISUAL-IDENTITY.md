# Visual identity

Status: initial direction
Applies to: terminal UI, documentation, future graphical surfaces

## Design thesis

The project is a dark-first workstation control surface: industrial in
material, precise in information, and energized by a narrow red signal.

The visual language draws on two broad traditions:

- industrial music design: severe hierarchy, monochrome structure, imperfect
  material, deliberate typography, and restrained tension;
- dark science-fiction interfaces: illuminated edges, deep layered surfaces,
  geometric paneling, and motion that communicates system activity.

This is an original system. It must not reproduce Nine Inch Nails marks,
mirrored letterforms, boxed logo construction, album artwork, TRON title
lettering, identity discs, costume circuitry, posters, or other franchise
assets.

### Research basis

The direction was formed by reviewing:

- the [official Nine Inch Nails discography](https://www.nin.com/discography/)
  and the breadth of its monochrome, degraded, typographic, and photographic
  systems rather than extracting a single album treatment;
- former NIN creative director Rob Sheridan's
  [portfolio and account of his art-direction practice](https://www.robsheridanproductions.com/art-direction),
  especially its emphasis on narrative, world-building, immersive systems, and
  the meeting of analog and digital methods;
- Disney's official
  [first-look image for *TRON: Ares*](https://thewaltdisneycompany.com/news/tron-ares-first-look/)
  and subsequent official imagery, which establish black material, red
  illuminated contours, hard geometric silhouettes, and deep negative space;
- Disney's description of the film as a collision between digital and physical
  worlds, with an
  [original Nine Inch Nails score](https://thewaltdisneycompany.com/news/disney-movies-theaters-fall-2025/).

These are research references, not an asset library. No source artwork belongs
in the repository.

## Principles

1. **Control surface, not decoration.** Every line, color, and transition
   communicates grouping, state, focus, or progress.
2. **Black carries the composition.** Dark space is the base material, not an
   area to fill.
3. **Red is a signal.** Use it for identity, current focus, and active
   operations. Do not wash entire screens in it.
4. **Status colors retain meaning.** Green means success, amber means caution,
   and error red is always paired with a label or symbol.
5. **Precision before grit.** Texture may appear in brand imagery at very low
   intensity. It never degrades terminal text, tables, or instructions.
6. **Quiet until active.** Resting screens are neutral. Energy appears at the
   selected edge, an executing step, or a changed state.
7. **Readable under failure.** Plain text, `NO_COLOR`, narrow terminals, logs,
   screen readers, and copied output remain first-class.

## Color language

### Graphical tokens

| Token | Value | Role |
|---|---:|---|
| `void` | `#070809` | page/background |
| `carbon` | `#0D1012` | primary surface |
| `gunmetal` | `#171B1F` | raised surface |
| `graphite` | `#292F34` | borders and dividers |
| `ash` | `#8B939A` | secondary text |
| `paper` | `#E8ECEF` | primary text |
| `hot-white` | `#FAFBFC` | titles and maximum emphasis |
| `signal` | `#E10600` | brand accent, focus rail, active progress |
| `signal-deep` | `#8A0000` | pressed/low-emphasis accent |
| `success` | `#5EDB82` | confirmed success only |
| `warning` | `#F0AD4E` | caution only |
| `failure` | `#FF5C70` | failures and destructive actions only |

Large dark surfaces should remain neutral. A typical screen should be at least
90% neutral by area. Glow is a graphical enhancement around a small active
edge, never a text effect.

### Terminal mapping

The shell theme uses ANSI 256-color approximations:

- primary text `252`; title `255`; muted `240`; border `238`;
- signal accent `160`;
- success `82`; warning `214`; failure `203`; informational text `250`.

The semantic shell aliases are `THEME_SIGNAL`, `THEME_STATUS_SUCCESS`,
`THEME_STATUS_WARNING`, `THEME_STATUS_FAILURE`, and `THEME_STATUS_MUTED`.
Compatibility names such as `THEME_ACCENT` and `THEME_ERROR` remain available,
but new renderers should use the semantic vocabulary.

Sixteen-color terminals fall back to standard red for the signal and preserve
green, yellow, and red for semantic status. `NO_COLOR` removes color without
removing hierarchy or labels.

The shared signal and failure colors must remain separate tokens even on
terminals whose limited palette renders them similarly. Labels and symbols
must always disambiguate navigation from failure.

## Typography

Terminal output uses the user's monospace font. Do not attempt terminal font
control.

For future graphical surfaces:

- UI and body: **IBM Plex Sans** or the system sans-serif stack;
- data, commands, paths, and telemetry: **IBM Plex Mono**;
- compact headings: **IBM Plex Sans Condensed**, with modest tracking.

Use weight, case, spacing, and alignment before introducing another typeface.
Sentence case is the default. Short technical markers such as `SYS`, `AUD`,
`PLAN`, and `BLOCKED` may use uppercase. Avoid extended all-caps copy,
decorative techno fonts, distressed text, mirrored letters, and custom
letterforms resembling either inspiration's official titles or marks.

## Geometry and composition

- Base spacing unit: 4 px; common gaps: 8, 12, 16, 24, and 32 px.
- Borders: 1 px neutral rules.
- Active edge: 2 px signal red.
- Corner radius: 0 to 3 px. Reserve clipped corners for one high-level element,
  not every panel.
- Panels: layered by luminance, not heavy shadows.
- Alignment: strong vertical rails, fixed label columns, and consistent numeric
  alignment.
- Density: operational and compact, with breathing room between sections.

The recurring original motif is the **control rail**: a red leading edge beside
the currently selected or executing object. It may terminate in a small square
node. It represents movement from observed state to intended state to an
approved action. It is not a recreation of TRON costume linework.

## Terminal component rules

### Lane headers

Use terse ASCII markers rather than pictorial emoji:

```text
CTL / Fedora workstation control
UPD / Fedora update
SET / Install workstation
SYS / System maintenance
DEV / Developer tools
ADR / Android research
AUD / Readiness report
HST / Host snapshot
DSK / Disk and memory
VRT / Virtualization
WEB / Web/database stack
PRF / Install profile
CLN / Cleanup
```

All lanes share the signal accent. Their written marker and title—not a
rainbow—carry identity.

### Status

Never communicate state by color alone:

```text
[OK]      SELinux enforcing
[WARN]    reboot recommended
[FAIL]    required service failed
[ABSENT]  adb not installed
[UNAVAIL] GPU sensor did not report
[SKIP]    database check intentionally deferred
```

### Actions

Use operational verbs and disclose effects:

```text
[1] Inspect host              read-only
[2] Build change plan         writes plan file
[3] Apply approved changes    sudo · changes system
[4] DANGER / Reset configuration
    destructive · confirmation required
```

Dangerous actions require both failure-red styling and explicit destructive
language. Brand signal red alone must not imply danger.

### Progress

Progress includes exact position and percentage:

```text
Progress  2/8  ####..............   25%
ACTION / Apply approved workstation plan
```

## Motion and light for future graphical UI

- interaction transitions: 120–180 ms;
- progress movement: linear and directional;
- glow: one low-opacity outer edge, no blooming body text;
- idle elements do not pulse;
- glitches may appear only in nonessential launch/brand moments and for less
  than 250 ms;
- honor `prefers-reduced-motion`;
- never delay a command or obscure a result for animation.

## Accessibility and terminal behavior

- `NO_COLOR` and `FEDORA_NO_COLOR=1` remove every semantic color token.
- ANSI 256-color, 16-color, and plain-text output preserve the same text order.
- Red/green distinctions are always paired with labels such as `[OK]`,
  `[WARN]`, and `[ERROR]`.
- Metadata remains readable on low-contrast terminal themes; dim styling is
  supplementary rather than the only hierarchy.
- Output order follows title, context, state, action, then detail so it remains
  meaningful to screen readers and captured logs.
- Decorative flicker and animation are not used in the terminal interface.
- Rules and sections are tested at 120, 100, 80, and 60 columns. `COLUMNS` may
  be supplied to preview width behavior without resizing a terminal.

## Imagery and texture

If future documentation or a graphical shell needs imagery, use original
abstract material:

- macro photographs of dark metal, powder coat, cable, ventilation, or tooling;
- sparse red practical light reflected across black surfaces;
- original diagrams, terminal traces, and machine geometry;
- subtle monochrome grain at 1–2% opacity outside text regions.

Do not use copied stills, posters, album art, logos, recognizable costumes,
light cycles, identity discs, NIN glyphs, or derivative title treatments.

## Voice

The interface voice is terse, calm, and accountable:

- prefer `Observed`, `Planned`, `Approval required`, `Applying`, `Verified`;
- state whether an operation is read-only or mutating;
- name the resource and outcome;
- avoid playful copy, faux-military language, and theatrical error messages.

## Current implementation

`lib/theme.sh` is the canonical terminal implementation. The first identity
pass establishes:

- a monochrome hierarchy with one shared signal-red lane accent;
- compact technical lane markers;
- status-only success, warning, and failure colors;
- dark, light, 256-color, 16-color, and no-color behavior.

Run `./theme_preview.sh` in an interactive terminal to inspect the component
system. Visual changes should be made centrally rather than with one-off ANSI
sequences in feature scripts.

Repository validation also audits the active menus, updater, monitor, and
health surfaces for retired pictorial markers and ambiguous lane names. New
control surfaces should be added to that audit when introduced.

## Review checklist

Before accepting a visual change:

- Does it improve hierarchy or system comprehension?
- Is it still clear with `NO_COLOR=1`?
- Is state expressed in text or shape as well as color?
- Is signal red focused rather than ambient?
- Does it preserve copy/paste-friendly output?
- Is it recognizably this project without borrowing protected marks or art?
- Does it feel serious after the novelty wears off?
