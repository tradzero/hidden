# macOS 27 experimental repair

Branch: `bugfix/macos27-calibrated-collapse` in `tradzero/hidden`.
This is an experimental compatibility build, not an upstream release.

## Behavior

On macOS 27+, measure the separator edge facing its neighboring status item,
search for a length that remains in the menu-bar layout, leave an 8pt margin,
and verify the final value. Each sample must settle across two reads. Searches
are bounded, cancellable and discarded when a newer layout request supersedes
them. A failed search restores the ordinary section to expanded and exposes a
notice in the context menu. A subsequent user toggle can retry.

Lengths are revalidated on reuse. Display changes/wake clear the cache. Frontmost
application changes first check whether the existing geometry still works to
avoid expanding the bar unnecessarily. The always-hidden separator has its own
calibration and retains a working span when the ordinary section expands.
Changing bar contents without an application/display event is rechecked on the
next toggle; this patch does not continuously poll other applications.

The macOS 26-and-earlier length and screen-change paths are retained. No new
Accessibility, Screen Recording, network or private-API dependency is added to
the application. First calibration (and invalidated calibration) can briefly
reveal items while probing. Always-hidden is not a confidentiality boundary.

## Evidence and limits

Apple documents that `NSStatusItem.isVisible` remains true when an item is
temporarily hidden due to insufficient space. Neither it nor a reported width
proves that another application's icons have actually disappeared:

- [Apple: isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)
- [Apple: length](https://developer.apple.com/documentation/appkit/nsstatusitem/length)
- [macOS 27 measurements informing the approach](https://github.com/dwarvesf/hidden/issues/360#issuecomment-5671149301)
- [Original calibration experiment](https://github.com/benjustjammin/hidden/commit/cd886af07d5139d8f02af2e6062b1bcef7359c10)

The pinned-edge classifier and its 24pt padding tolerance remain empirical.
An accepted span does **not** prove full hiding on every display. Mixed-width
displays, notched displays, RTL, fullscreen transitions, physical hot-plug and
sleep/wake still need hardware acceptance. This patch does not implement the
multiple-spacer migration proposed in upstream PR #392.

## Validation on 2026-09-15

Host: macOS 27.0 (26A428), two 1920x1080 logical displays.

- Standalone real-menu-bar probe: 160/300pt kept the relative edge at -8pt;
  600pt moved it to +292pt, increasing further with larger requests. Restoring
  20pt restored the original position. These are geometry measurements only.
- Nine deterministic tests pass against the production calibrator: boundary,
  cache reuse, stale cache, cancellation, superseded generation, missing
  geometry/retry, no-fit, anchor movement and display-context movement.
- Production-controller integration passes ordinary collapse/expand,
  cancellation during calibration, recollapse and final expansion. A synthetic
  screen-change notification invalidates the cache; no display settings change.
- With always-hidden enabled, independent lengths measured about 459pt and
  481pt for the always-hidden and ordinary separators respectively. Later runs
  ranged from 421–481pt as the available layout changed; these are not constants.
- A real integration run exposed image reassignment resetting the calibrated
  width to 20pt on macOS 27. The controller now avoids redundant image writes.
- Full app compilation, including storyboard/assets and the pinned HotKey
  dependency, runs in GitHub Actions. The local machine has Command Line Tools
  but no Xcode/ibtool, so local tests compile a controller harness with Swift 6.4.
- Cross-process visual E2E was attempted with independent HB-A/HB-B decoys.
  The test process has no AX/capture permissions; the existing UI tool timed out
  retrieving the test application's tree, and its MenuBarAgent screenshot did
  not provide a usable composed view. **Cross-process visibility/click E2E is
  not marked passed.** No permissions were granted and no installed app was
  replaced. Test processes exited and their temporary status items were removed.

The controller harness uses the real controller, calibrator, preferences and
timer code. It stubs only preferences-window/login integration, has an isolated
bundle ID, and resets only its own preferences. It is not a full app UI test.
Do not publish raw desktop/AX captures in this public fork.

## Reproduce

```sh
bash scripts/test-calibration.sh
bash scripts/build-controller-integration.sh
build/HiddenBarIntegration.app/Contents/MacOS/HiddenBarIntegration
build/HiddenBarIntegration.app/Contents/MacOS/HiddenBarIntegration --always-hidden
```

The integration tests require a logged-in macOS 27 graphical session with enough
room for the test items. Exit status is nonzero on assertion failure. `--hold`
keeps the harness alive for manual inspection, with a three-minute safety exit.

For full UI acceptance, run the Actions-built trial app, place independent decoy
items left of its separator, then capture the **entire** menu bar on **each**
display. Verify disappearance on collapse, restoration and actual clicks on
expand, cancellation, always-hidden, app menu changes and display changes.

The Actions artifact uses `com.tradzero.hidden.macos27trial` to keep its settings
separate from the installed upstream app. It is unsigned/unnotarized development
software. To smoke-test without login-item migration or first-launch preferences:

```sh
'Hidden Bar.app/Contents/MacOS/Hidden Bar' \
  -smAppServiceMigrated YES -isAutoStart NO -isShowPreference NO -isAutoHide NO
```

Upstream's review-team requirement for core geometry/state changes remains a
pre-merge requirement; this fork has not been submitted or merged upstream.

## Menu bar icon and accessibility follow-up (2026-09-15)

- Replaced the old heavy bitmap arrows with cached 12pt medium-weight SF Symbol
  single chevrons on macOS 11+, retaining the bitmap fallback on older systems.
  Template rendering follows system appearance; direction still follows LTR/RTL.
- Added localized action tooltips and accessibility labels (English, Simplified
  and Traditional Chinese). No double-chevron or extra status item was added.
- Fixed the existing button action ignoring non-mouse activation. Accessibility
  activation now performs the primary expand/collapse action; mouse right-click
  and Option-click retain their context-menu/separator actions.
- The controller harness now exercises `performClick(nil)` and checks the action
  description after expansion, in addition to cancellation and recalibration.
- Using the UI automation tool on the macOS 27 graphical session, clicking the
  actual harness status button changed its accessible description from `Hide
  icons` to `Show hidden icons`; clicking again restored `Hide icons`. This failed
  before the non-mouse action fix. The harness uses the production controller.
- The tool could read the full trial app's preferences window. Its menu-bar
  screenshot still omitted most status icons, and direct selection of the
  windowless harness timed out. Full visual disappearance/restoration of other
  apps' icons across both displays remains unverified. Accessible labels alone
  do not prove that those icons were hidden.
- Follow-up regression results: 9 deterministic calibrator tests passed; the
  ordinary controller run passed 6 assertions and always-hidden passed 7. The
  old fixed-second harness produced a premature recollapse failure while the
  two-stage calibration was still running. The harness now waits for idle with
  a 30-second deadline and fails explicitly on timeout; both modes passed.
