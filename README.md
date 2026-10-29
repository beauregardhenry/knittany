# Knitting

A Mac app (Intel and Apple Silicon, macOS 15 Sequoia or later) that regrades
knitting patterns to the wearer's measurements: between or beyond the
published sizes, or with specific changes such as a longer body or wider hips.

## Layout

| Folder | What it is |
|---|---|
| `KnitCore/` | Swift package: `KnitCore` (the knitting maths and the library of people, patterns and projects), `KnitRender` (schematic and chart drawing, PDF export), the `knit` command-line tool, and the tests |
| `App/` | The Mac app (SwiftUI). `project.yml` generates `Knitting.xcodeproj` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| `Patterns/` | Encoded patterns. **Not in git** (see below) |

## How regrading works

A pattern is stored as a parametric model (a JSON file):

- **Schematic**: the designer's finished measurements per size (chest, upper arm, hem, …).
- **Quantities**: every number that changes between sizes. A quantity is either
  *graded* (it follows one schematic measurement, using the designer's own numbers
  to interpolate between or beyond sizes) or a *formula* over other quantities
  (`backCO - 2*underarmEvents`, `nearestMod(alineFront, 3, 1)` for a 2x1 rib, …).
- **Sections**: the instructions as templates (`CO {backCO} sts`,
  `{if cuffAdj > 0}…{end}`), so the text always matches the numbers.
- **Checks**: conditions that must hold, such as "the pockets still fit on the fronts".

Body measurements turn into finished measurements with ease: the designer's
stated ease where there is one, otherwise ease inferred by comparing the
pattern's sizes with the Craft Yarn Council standard body measurements. If
your gauge differs from the pattern's, stitch and row counts are rescaled.

### Designer check

`knit check` tests a pattern file against the designer's own numbers:

1. every formula reproduces the designer's printed totals in every size;
2. grading to each size's own measurements gives back every number exactly;
3. hiding one size and regrading to it from the others lands on or next to the
   designer's numbers (Dipped Arms: 160/189 stitch counts exact, 188 within 2;
   all sleeve-decrease spacings exact).

## Build and test

```bash
cd KnitCore && swift test
```

```bash
cd KnitCore && swift run knit regrade ../Patterns/dipped-arms.json --chest 37in --upper-arm 11.5in --units in
```

```bash
cd KnitCore && swift run knit check ../Patterns/dipped-arms.json
```

```bash
cd App && xcodegen generate && xcodebuild -project Knitting.xcodeproj -scheme Knitting -configuration Release -destination 'generic/platform=macOS' -derivedDataPath ../build/DerivedData build
```

The app is ad-hoc signed for now; Developer ID signing and notarization come
once the Apple Developer account is set up.

## Using the app

1. **People**: add the person and type the body measurements you've taken (inches or cm). Grey values are Craft Yarn Council estimates for reference; regrading uses only what you measured.
2. **Patterns**: import a pattern file, then attach the original PDF so its chart pages are included.
3. **New Project** (on the pattern): pick the person and version. The right side shows the regraded pattern exactly as it exports. Adjust ease, type a finished measurement to change it (a longer body, say), or enter your swatch gauge. **Export PDF…** saves it.

Everything is kept as plain files in `~/Library/Application Support/Knitting/` (backed up by Time Machine). Deleted patterns go to the Trash.

## Pattern files and this public repo

Encoded patterns contain the designers' instructions, so `Patterns/` is
git-ignored while this repository is public. Tests that need a real pattern
are skipped when its file isn't there. `KnitCore/Tests/KnitCoreTests/Fixtures/`
holds a made-up pattern that is safe to publish.

## Roadmap

1. ✅ Engine, Dipped Arms, designer check, text output
2. ✅ Mac app: people and measurements, pattern library, projects, schematic and chart drawings, PDF export
3. PDF import: offline (default) and AI-assisted (optional), with a check-and-correct screen
4. Circular yoke (Marled Mania)
5. Raglan and set-in sleeves, then other top-down constructions
6. Signing and notarization
7. Bottom-up and seamed sweaters
8. Later: new patterns from the knitter's design choices
