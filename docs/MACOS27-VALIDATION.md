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

During a process lifetime, lengths are cached for the current display configuration
(display IDs, logical frames, backing scale, safe-area insets, separate-Spaces
setting and LTR/RTL). Unchanged application activation, wake or screen notifications
perform no layout writes. A changed configuration invalidates both section caches;
ordinary expand/collapse directly uses the cached value without probing again.
The context menu offers **Recalculate hiding layout** for manual recovery after
rearranging items or an unexpected layout problem. A process restart recalibrates;
lengths are not persisted across OS/app updates.

Each section has six additional spacers. Calibration seeks a conservative unit,
with a ceiling of `narrowest logical width / 4`
rather than the current foreground menu's maximum. This candidate is probed first;
if rejected, the bounded search finds a smaller accepted length. This is an empirical heuristic,
not an Apple API guarantee. The seven-unit span still needs validation on unusually
disparate displays. An unsettled search retries once after 500ms, retaining the
same cancellation token. Spacers are invisible and zero-length when their section
is expanded/disabled. The always-hidden group remains active on ordinary expansion.

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
sleep/wake still need hardware acceptance. The multi-spacer approach is informed
by [upstream PR #392](https://github.com/dwarvesf/hidden/pull/392), with calibrated
rather than fixed per-item lengths and independent always-hidden spacers.
Six spacers per section is a fixed registration budget; this is not a guarantee
for arbitrarily disparate display sizes or every macOS 27 layout.

## One-time layout migration for the multi-spacer build

macOS 27 owns status-item placement. To register spacers between the arrow and
separator, this version uses new `_wide_v1` autosave names, registered in a fixed
order. Older versions' names are untouched for rollback. The always-hidden slots
are registered even when disabled, then hidden, so enabling that section does not
create a misplaced group at the left edge.

On the first launch, expand using Hidden Bar's single arrow, then hold Command
and drag the icons to hide to the **left of its separator**. Keep always-visible
icons to the right of the arrow. If using always-hidden, place those icons to
the left of the additional separator. Do not drag icons between a separator and
its arrow; that space belongs to the hidden spacers. This grouping is a one-time
setup and is retained on subsequent launches. The system double-chevron is
unchanged. Active spacer items have no glyph and request zero width on expansion; macOS may retain small gaps between their slots.

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

## Short-menu residual icons follow-up (2026-09-15)

The user reproduced residual icons in Telegram without clicking either arrow;
Chrome's longer menu hid them. A trial that invalidated the cache on application
activation still leaked icons, so cache invalidation alone is not the fix.
The final change adds the spacer groups described above as well as invalidation.

In the isolated production-controller harness, two independent-process status
items (`HB-A`, `HB-B`) were visible in MenuBarAgent's accessibility tree when
expanded. UI-tool clicks produced this sequence:

1. Click `HB-A`: its title became `HB-A!` and its process logged the action.
2. Click the controller's status button to collapse: both decoy items were absent
   from a fresh full MenuBarAgent tree; the controller offered `Show hidden icons`.
3. Click to expand: both decoys reappeared; clicking `HB-A!` restored `HB-A` and
   logged a second action in the independent process.

This verifies disappearance/restoration and live input through the system menu
bar, beyond checking the controller's own arrow or a reported window width. It
is not an all-displays screenshot test; no raw desktop/AX captures are committed.
The complete local application also compiles against the installed macOS 27 SDK,
using the locked HotKey revision and previously CI-compiled storyboard/assets.

Final focused results: 9 calibrator unit tests, 13 ordinary-controller assertions,
and 19 always-hidden-controller assertions passed. Controller coverage includes
fresh calibration after activation, cancellation, expanded intent, spacer cleanup,
and preserving the always-hidden slots across disable/re-enable.


## Display-cache and grouping follow-up (2026-09-16)

The production autosave names remain `_wide_v1`; this update does not introduce
another layout migration. Local Xcode builds and Actions now use the same fork
bundle ID, `com.tradzero.hidden.macos27trial`. Updates should replace the app at
its existing path instead of launching successively named trial directories.
The upstream app retains its separate `com.dwarvesv.minimalbar` identity.

Hidden/visible membership is positional, saved by macOS via the status items'
autosave names; the app does not own an independent list of other apps' icons.
Stable identifiers and in-place updates preserve that existing mechanism. No
private host-layout preference keys or cross-app permissions are introduced.
A system reset of those positions may still require manual regrouping.

The integration harness injects a display-configuration key to test invalidation
without changing the user's physical display settings. It verifies that repeated
activation/wake and same-configuration screen events leave the layout generation
and widths unchanged, cached collapse is synchronous, a changed configuration
invalidates the cache, and manual recalibration is cancellable.

Focused validation: 12 calibrator checks, 16 ordinary-controller assertions and
22 always-hidden-controller assertions passed. Both sections selected 325pt on
the two 1920pt displays. A transient unsettled ordinary recalibration occurred
in an earlier run; the bounded retry was added and both final runs passed.
Physical hot-plug and display-mode changes remain hardware acceptance items.

The initial 325pt profile passed controller checks but the user reported residual
icons in Telegram. It was rejected as a release candidate: summed item widths
alone do not prove real hiding. Restoring the original linker identifier did not
resolve that symptom. The revised candidate is one quarter of the narrowest
logical screen width (480pt here), close to the prior visually accepted 481pt.
Local executable staging must retain the basename `Hidden Bar`; compiling to
`cache-Hidden-Bar` changed the ad-hoc linker identifier even with an unchanged
bundle ID. The CI executable already uses `Hidden Bar`.


## Slot-order repair and acceptance (2026-09-16)

The 480pt cache profile alone left two icons visible, and reducing the edge
probe tolerance from 24pt to 8pt did not resolve existing grouping. The stricter
classifier is retained: a new 18pt-ejection regression fails with the old
24pt tolerance and passes with 8pt. This remains an empirical layout signal,
not proof that another app's icon is hidden.

The actual grouping defect was `isVisible=false` on expansion. In an isolated
native experiment, eight 20pt items started in order (right control, six spacers,
left separator). Hiding/re-showing the six spacers moved the separator from
x=508 to x=670, next to the right control at x=697, with the spacers reinserted
on its left. This occurred without user dragging. Repeating the experiment with
zero widths and retained visibility preserved every position. The user confirms
having moved application icons, not the separator.

Active spacer slots now remain visible and request zero width on expansion.
The host can retain small inter-item gaps. Only the disabled always-hidden
section is removed; ordinary expansion no longer removes/reinserts its slots.
Application activation still performs no layout writes for the same display
configuration. Existing bundle ID, executable basename, path and `_wide_v1`
autosave names are unchanged.

Diagnostics (`-HiddenBarLayoutDiagnostics YES`) log only our own item frames and
briefly show compact slots on startup. Reads can be stale, and overlapping or
offscreen frames must not be interpreted as proof of hiding. The installed
trial's compact group had a 244pt gap between its spacers and separator,
consistent with application icons being inside the disrupted group.

For the already disrupted layout, the temporary launch option
`-HiddenBarArrangeGroup YES -isAutoHide NO` labels the six existing slots 1–6.
The user Cmd-dragged these labels between the separator and arrow, leaving app
icons in place, then clicked the arrow. Arrangement state survives activation
and screen notifications and clears the labels only on an explicit toggle.
Normal launches omit these temporary options.

**User acceptance:** after the slot correction, all icons hid. After a normal
restart with arrangement/diagnostic/auto-hide overrides removed, the user
confirmed the grouping survived and Telegram, ChatGPT and Chrome hid correctly
without flickering on application switches. This verifies the current machine
and configuration, not arbitrary hardware or all future menu-bar changes.

Validation:

- 13 deterministic calibration checks, including the 18pt ejection regression.
- 17 ordinary-controller and 23 always-hidden-controller assertions.
- Four arrangement lifecycle assertions (startup, activation/display changes,
  label cleanup and explicit collapse).
- Real native zero-width slot-order regression
  (`tests/SpacerOrderIntegration.swift`); `--legacy-hide` reproduces the old
  remove/reinsert operation. Run with other Hidden Bar instances stopped;
  overflow makes this test explicitly inconclusive.
- Full local Swift compilation against SDK 27, locked HotKey revision and the
  existing compiled storyboards/resources. Local signature identifier remains
  `Hidden Bar`; bundle ID remains `com.tradzero.hidden.macos27trial`.

The controller harness additionally waits beyond the 300ms click debounce after
fast cache hits, and asserts activation tests begin collapsed, avoiding vacuous
cache passes. Physical display hot-plug, mixed scaling, RTL and notched hardware
remain separate acceptance cases.
