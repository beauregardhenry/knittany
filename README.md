# Knittany

A Mac app (Intel and Apple Silicon, macOS 15 Sequoia or later) that regrades
knitting patterns to the wearer's measurements: between or beyond the
published sizes, or with specific changes such as a longer body or wider hips.

## Layout

| Folder | What it is |
|---|---|
| `KnitCore/` | Swift package: `KnitCore` (the knitting maths and the library of people, patterns and projects), `KnitRender` (schematic and chart drawing, PDF export), `KnitImport` (reading pattern PDFs), the `knit` command-line tool, and the tests |
| `App/` | The Mac app (SwiftUI). `project.yml` generates `Knittany.xcodeproj` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
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

### Patterns whose structure changes with size

Some designs can't be interpolated number by number. Marled Mania's ribbed
yoke widens its ribs one stitch at a time (2x2, 3x3, …) until they reach the
size's rib width w, and every later count is a multiple of w; that's why the
PDF has "Size 2 only" steps. Its model makes the same design choices a
designer would: round w to the nearer size, adjust the number of ribs so the
yoke ends at the right width (the neck changes a little), split the ribs
between back, sleeves and the drapey fronts from the target measurements, and
include only the yoke stages that size needs. The designer check reproduces
all three sizes exactly and gets the middle size exactly when it's hidden.

### Raglans

In a raglan the same increases widen the body and the sleeves, so the bust is
tied to the upper arm (for the stripey raglan, bust = 2 × arm + 28 sts), and
the number of increase rows ties both to the yoke depth. The raglan model
undoes those ties the way a designer would: body-only or sleeve-only
increase rows when the arm and bust don't match the designer's proportions,
increases moved onto WS rows ("rapid increases") when the yoke must be
shallower, and plain rows when it must be deeper. Sleeve decreases are
spaced to fit the designer's sleeve length, on whole stripes.

## Designing a sweater from scratch

**Design a Sweater…** (⇧⌘D) writes a new pattern from the knitter's choices:
a top-down raglan or round yoke, pullover or cardigan, crew or wide neck, fit
(close to oversized), length, body shape, sleeve length and shape, edge
finishes (2x2 or 1x1 rib, garter, rolled), stripes, and the swatch gauge.

The design is drawn for the Craft Yarn Council's women's sizes (XS–5X) or men's sizes (S–5X), using
their body measurements plus the ease of the chosen fit. Every stitch and row
count is a formula over the finished measurements and the gauge, so the
result is an ordinary pattern: a project regrades it to anyone's
measurements, with a schematic, PDF and knitting mode. Raglans use the same
body-only, sleeve-only and rapid increases as the raglan model; round yokes
spread their increases over three to six rounds, so no round more than about
doubles the stitches. **Edit Design…** on a designed pattern changes the choices
later. `knit design construction=yoke garment=cardigan …` does the same from
the command line.

## Importing a pattern PDF

A PDF is read into a *draft* that the knitter checks before it's saved:

- **On this Mac (default).** The text is put back in reading order (pattern
  PDFs are usually in columns), scanned pages are read with OCR, and the usual
  conventions are picked out: the sizes ("S (M, L)" or "1 [2, 3]"), gauge,
  ease, finished measurements and size tables. Every number written per size,
  like "CO 142 (148, 154) sts", becomes a value graded along the measurement
  it follows most closely, and its sentence becomes a template.
- **With Claude (optional).** The PDF is sent to Anthropic's API, which returns
  the same draft. Better for unusual layouts and schematics. Needs an API key
  in Settings, stored in the keychain.

The review screen shows the original PDF beside the draft: sizes and gauge,
which garment measurement each row of the size table is, what each number is
and what it follows, the instructions (sections can be left out), and which
original pages (charts) to print with the regraded pattern. Steps written for
some sizes only are kept as written and flagged.

An imported pattern grades number by number. It doesn't know the designer's
formulas the way a hand-encoded pattern (like Dipped Arms) does, so there are
no consistency checks; read the regraded instructions through once.

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
cd KnitCore && swift run knit read ../Patterns/dipped-arms.pdf --pattern /tmp/dipped-arms-imported.json
```

```bash
cd App && xcodegen generate && xcodebuild -project Knittany.xcodeproj -scheme Knittany -configuration Release -destination 'generic/platform=macOS' -derivedDataPath ../build/DerivedData build
```

The app is ad-hoc signed for now. Once the Apple Developer account is set up,
`scripts/release.sh` builds, signs with Developer ID, notarizes and staples
the app (the one-time setup is at the top of the script).

## CI and releases

GitHub Actions runs on every pull request and push to main (`.github/workflows/`):

- **CI**: banned patterns (`as!`, `fatalError(`, `print(`, TODO/FIXME) stay at zero; the test
  count and line coverage of the KnitCore package may not drop below their floors; the tests
  run on Apple silicon and Intel; the checked-in Xcode project must list every app source;
  the universal app is built and its bundle checked.
- **Ratchets**: after a merge to main, `test-count-ratchet` and `coverage-ratchet` raise
  `test-count-baseline.txt` and `coverage-baseline.txt` when the numbers climb. Don't bump
  those files from a branch.
- **Releases**: push an annotated tag matching `MARKETING_VERSION` in `App/project.yml`
  (e.g. `git tag -a v0.1.0 -m "Knittany 0.1.0"`), with
  `DistributionAssets/RELEASE NOTES - Knittany <version>.md` in place. The release workflow
  tests on both architectures, packages a ZIP and DMG with checksums and an SBOM, attests them,
  and publishes the GitHub release. Run it by hand for a release candidate.

The same checks run locally: `./scripts/check-coverage.sh`, `./scripts/build-app.sh`,
`./scripts/package-release.sh` and so on. Tests that need the git-ignored pattern files are
skipped on CI, so CI's coverage is a little lower than a local run's.

## Using the app

1. **People**: add the person, choose the women's or men's size chart, and type the body measurements you've taken (inches or cm). Grey values are Craft Yarn Council estimates from that chart, for reference; regrading uses only what you measured.
2. **Patterns**: **Import Pattern…** (⌘I) a PDF, or open a PDF with Knittany, and check the draft before saving. Pattern files (`.json`) import directly; attach the original PDF so its chart pages are included.
3. **New Project** (on the pattern): pick the person and version. If the pattern doesn't state its ease, enter the ease you want under Ease. The right side shows the regraded pattern exactly as it exports. Adjust ease, type a finished measurement to change it (a longer body, say), or enter your swatch gauge. **Export PDF…** saves it.

4. **Text size**: Knittany > Settings, or View > Bigger Text (⌘=) and Smaller Text (⌘−), makes the text Large or Extra Large throughout the app, in Knit mode and in exported PDFs.
5. **Knit**: switch the project to Knit for a checklist of every step, with the next step highlighted and a row counter (`-` and `=` keys). Progress is saved with the project.

Everything is kept as plain files in `~/Library/Application Support/Knittany/` (backed up by Time Machine). Deleted patterns go to the Trash.

## Pattern files and this public repo

Encoded patterns contain the designers' instructions, so `Patterns/` is
git-ignored while this repository is public. Tests that need a real pattern
are skipped when its file isn't there. `KnitCore/Tests/KnitCoreTests/Fixtures/`
holds a made-up pattern that is safe to publish.

## Roadmap

1. ✅ Engine, Dipped Arms, designer check, text output
2. ✅ Mac app: people and measurements, pattern library, projects, schematic and chart drawings, PDF export
3. ✅ PDF import: offline (default) and with Claude (optional), with a check-and-correct screen
4. ✅ Circular yoke (Marled Mania)
5. Raglan ✅ (stripey raglan), then set-in sleeves and other top-down constructions
6. Signing and notarization
7. Bottom-up and seamed sweaters
8. ✅ New patterns from the knitter's design choices (top-down raglan and round yoke); more constructions later
