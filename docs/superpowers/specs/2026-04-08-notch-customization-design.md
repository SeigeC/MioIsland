# CodeIsland Notch Customization — Design Spec

**Date:** 2026-04-08
**Status:** Draft (pending review)
**Target version:** v1.10.0
**Author:** Brainstorming session with project owner

## 1. Background

CodeIsland today renders a fixed black-on-white notch overlay locked to
the MacBook Pro hardware notch. All colors, fonts, notch dimensions, and
buddy/usage-bar visibility are hardcoded. Users cannot customize any
appearance or layout aspect of the notch, and the idle-state notch is
always as wide as its maximum expanded state — leaving large empty
space in the middle of the menu bar even when there is almost nothing
to show.

This spec defines a set of seven user-facing customization features and
the supporting architecture to deliver them in v1.10.0 as a single
release.

## 2. Goals

1. Let the user hide the buddy (pet) indicator via a setting.
2. Let the user hide the usage-bar (rate-limit %) indicator via a
   setting.
3. Let the user resize the notch via an in-place live edit mode on the
   notch body itself, covering both MacBooks with and without a
   hardware notch.
4. Let the user slide the notch horizontally along the top edge of the
   screen (not free-floating).
5. Let the user pick a theme from six built-in presets, with smooth
   color transitions on switch.
6. Make the notch auto-shrink to fit its content at idle and expand up
   to a user-configured maximum width when content grows.
7. Let the user scale all notch fonts via a four-step size picker.

## 3. Non-goals

- Fully free-floating notch positioning (rejected: breaks the notch's
  visual identity; hardware notch on the Mac remains regardless).
- User-defined custom themes with color pickers (rejected this round:
  six curated presets cover the intent; a future iteration can add a
  custom palette editor without breaking the current architecture).
- Vertical resizing of the notch (rejected: height is a visual
  signature; hardware notch height is fixed at ~37pt).
- Undo/redo history beyond a single Cancel-to-origin rollback in live
  edit mode.
- Refactoring `@AppStorage` keys unrelated to the notch (notifications,
  CodeLight, behavior tabs stay untouched).
- Changing the notarization / release pipeline.

## 4. User-facing design

### 4.1 Settings surface

A new "Notch" section is added inside the existing **Appearance** tab
of `SystemSettingsView`. No new top-level tab.

```
Appearance Tab
  ...existing controls...

  ─── Notch ───

  Theme              [ Classic       ▾ ]      ← 6 presets, mini swatch in each row
  Font Size          [ S | M | L | XL ]       ← Segmented picker
  Show Buddy         [   ]                    ← Toggle
  Show Usage Bar     [   ]                    ← Toggle
  Hardware Notch     [ Auto          ▾ ]      ← Auto | Force Virtual (2 cases)
  [ Customize Size & Position… ]              ← Big button → enter live edit mode
```

### 4.2 Live edit mode

A one-shot interaction that takes over the notch itself to let the user
resize, reposition, and preview the geometry. Entered from the
Customize button in Settings.

#### Window model

Live edit mode adds a **new auxiliary `NSPanel` subclass**,
`NotchLiveEditPanel`, separate from `NotchPanel`. Its purpose:

- Hosts the floating edit controls (arrow buttons, Notch Preset, Drag
  Mode, Save, Cancel).
- Because controls are clickable, the panel must become key.
  `styleMask = [.borderless, .nonactivatingPanel]`,
  `isMovableByWindowBackground = false`, `canBecomeKey = true`,
  `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`.
- Frame: the panel is sized to the full screen width (so the arrow
  buttons can live outside the notch's narrow bounds) and positioned
  flush with the top of the active screen. Its height covers the
  notch area plus the space for the controls beneath (~160pt total).
- The panel renders a transparent background so only the controls are
  visible; clicks on transparent areas pass through (`ignoresMouseEvents`
  set per subview via `NSView.hitTest` override).
- Created by `NotchWindowController.enterLiveEditMode()`, torn down by
  `exitLiveEditMode()`. Lifetime is strictly scoped to `store.isEditing`.
- `NotchPanel` itself stays non-key (`canBecomeKey = false`) and
  unchanged — the notch content is still drawn by `NotchView`, but the
  overlay window above it catches the clicks.

While in edit mode:

- The notch (inside `NotchPanel`) shows **simulated Claude content**
  driven by `NotchLiveEditSimulator` (see timing below).
- A **dashed border** and a **soft neon-green breathing gradient**
  surround the notch (implemented inside `NotchView`, conditioned on
  `store.isEditing`).
- The `SystemSettingsWindow` is minimized/hidden so the user can see
  the real notch. On Save or Cancel, the Settings window is re-shown.

#### Simulated content rotation

Driven by `TimelineView(.periodic(from: .now, by: 2))` scoped to
`NotchLiveEditSimulator`. Lifecycle rules:

1. Timeline runs only while `store.isEditing == true`. Leaving live
   edit mode ends the timeline automatically via view lifetime.
2. **Rotation pauses during an active resize or drag gesture.** While
   the user is mid-gesture, the simulator freezes on the current
   message so the notch width changes in response to user input, not
   in response to auto-rotation. Implementation: the timeline's
   `context.date` is gated through a `@State var isInteracting: Bool`.
3. Rotation resumes 0.8s after the last gesture ends (de-bounce).
4. Messages rotate through 5 fixtures: empty / short / medium / long /
   long-with-wrap. See `NotchLiveEditSimulator.fixtures`.

#### Control layout

The auxiliary panel hosts the following controls, positioned relative
to the notch frame:

```
               ┌─────────────────────────────┐
               │   [simulated Claude text]   │
               └─────────────────────────────┘
          ◀                                         ▶       ← Neon green arrow buttons (resize)

                [⊙ Notch Preset]  [✋ Drag Mode]              ← Action buttons

                     [ Save ]    [ Cancel ]                  ← Neon green / neon pink
```

Interactions:

- **Arrow buttons (◀ ▶):** one click = symmetric (mirror) resize by
  2pt. `⌘+click` = 10pt. `⌥+click` = 1pt. Resize always shrinks/grows
  the notch around its current center.
- **Drag on the left/right edge of the notch:** continuous mirror
  resize, equivalent to the arrow buttons.
- **Notch Preset button:** sets `maxWidth = hardwareNotchWidth + 20pt`
  (with small breathing room). Also flashes a dashed width marker
  underneath the notch for 2s so the user sees the hardware notch
  reference width. **Enabled iff effective `hasHardwareNotch == true`**
  (i.e., whenever a real hardware notch is detected *and* the user has
  not overridden with `.forceVirtual`). Otherwise disabled with help
  tooltip: *"Your device doesn't have a hardware notch"*. This rule
  holds regardless of how the mode was selected.
- **Drag Mode button:** toggles the edit sub-mode between `.resize`
  (default) and `.drag`. On each toggle, the entire notch flashes once:
  opacity animates `1.0 → 0.4 → 1.0` over 0.3s total with
  `.easeInOut`. While in `.drag`, dragging the notch moves it
  **horizontally only** along the top edge of the screen — y is
  locked to the top. Click Drag Mode again to return to `.resize`.
- **Save (neon green):** commits all changes made during the edit
  session via `store.commitEdit()`, tears down the overlay, restores
  the Settings window. **Works in both `.resize` and `.drag`
  sub-modes** — the sub-mode is transient and does not gate Save.
- **Cancel (neon pink):** rolls back all changes to the snapshot taken
  at `enterEditMode()` via `store.cancelEdit()`, tears down the
  overlay, restores the Settings window. **Works in both sub-modes.**
  `editSubMode` is transient state owned by `NotchLiveEditOverlay`; it
  is not persisted and dies with the overlay — cancelling while in
  `.drag` fully exits live edit and restores the pre-edit snapshot,
  including rolling back any horizontal offset changes.

#### Edit sub-mode state machine

```
         enterEditMode()              commitEdit() / cancelEdit()
  (idle) ─────────────▶ .resize ─┐ ────────────────────────▶ (idle)
                           ▲     │
                           │     ▼
                 [Drag Mode button] ⇆ .drag
```

- `editSubMode` is local state inside `NotchLiveEditOverlay` (SwiftUI
  `@State`).
- All transitions flash the notch (`.resize ↔ .drag`) or play the save
  / cancel teardown animation.
- Save and Cancel are valid from any sub-mode.

### 4.3 Runtime auto-width behavior

At runtime, the notch width is computed every frame as:

```
clampedWidth = max(minIdleWidth,
                   min(desiredContentWidth, store.customization.maxWidth))
```

- `minIdleWidth = 140pt` — a hard floor chosen to guarantee that the
  notch never becomes narrower than "pet icon + 3-char status label
  + 1-tiny-indicator" at the default font scale. This is smaller than
  any realistic idle content, so the clamp effectively lets the notch
  shrink tight around actual content (the user's reference screenshot
  at 260pt still has plenty of headroom above 140pt).
- `desiredContentWidth` — measured via `GeometryReader` +
  `PreferenceKey` from the actual rendered notch content. **Includes
  the current font scale's effect on text sizing** — see the font
  scale interaction rule below.
- Width changes are animated with `.spring(response: 0.35,
  dampingFraction: 0.8)` so transitions are smooth.
- When `desiredContentWidth > maxWidth`, the offending text uses
  `.lineLimit(1).truncationMode(.tail)` to render with an ellipsis.

#### Font scale × auto-width interaction

**`maxWidth` is sacrosanct** — it is the user's explicit cap and is
never auto-bumped by a font scale change. The interaction rules:

1. When the user switches font scale (Appearance picker), text re-lays
   out at the new size. `GeometryReader` re-measures
   `desiredContentWidth` on the next frame.
2. The new desired width flows through the same clamp formula. If the
   scaled content now fits within the user's `maxWidth`, the notch
   grows to fit it (up to `maxWidth`).
3. If the scaled content exceeds `maxWidth`, truncation with tail
   ellipsis kicks in immediately. The notch width stays pinned at
   `maxWidth`; the user sees more `…` in long messages.
4. The clamp transition is animated with the same spring, so font
   size changes look smooth even when they trigger width changes.

To get more room at XL scale, the user must explicitly enter live edit
mode and bump `maxWidth`. There is no "effective max width = maxWidth
× fontScale" scaling — that would make the `maxWidth` setting
confusing ("why is my 440pt notch now 572pt at XL?").

Effect: idle state shrinks the notch tightly around its sparse content,
solving the "huge empty middle" problem in the user's screenshot.

### 4.4 Theme switching

Switching the theme picker immediately mutates
`store.customization.theme`. All views reading palette colors re-render.

#### Animation scoping (critical)

Naïvely applying `.animation(.easeInOut(duration: 0.3), value: theme)`
at the `NotchView` root would stack on top of the width spring and
could visually interfere with in-flight geometry animations. Instead,
color interpolation is scoped **only to color-bearing modifiers**
via a dedicated view modifier:

```swift
struct NotchPaletteModifier: ViewModifier {
    @EnvironmentObject var store: NotchCustomizationStore
    func body(content: Content) -> some View {
        content
            .foregroundColor(store.palette.fg)
            .background(store.palette.bg)
            .animation(.easeInOut(duration: 0.3), value: store.customization.theme)
    }
}
```

Because the `.animation(_:value:)` variant with a `value` parameter
triggers only when `theme` changes, and only re-animates the modifiers
it directly scopes, geometry animations (width spring) are not
retriggered by theme switches. Theme and geometry transitions can
happen simultaneously without interfering.

Status colors (success / warning / error) come from Asset Catalog
entries under `NotchStatus/` and are **not** palette-controlled —
they preserve semantic meaning across themes.

## 5. Architecture

### 5.1 State model

A single value type persists all notch customization state:

```swift
struct NotchCustomization: Codable, Equatable {
    var theme: NotchThemeID = .classic
    var fontScale: FontScale = .default
    var showBuddy: Bool = true
    var showUsageBar: Bool = true
    var maxWidth: CGFloat = 440
    var horizontalOffset: CGFloat = 0
    var hardwareNotchMode: HardwareNotchMode = .auto

    static let `default` = NotchCustomization()
}

enum NotchThemeID: String, Codable, CaseIterable, Identifiable {
    case classic, paper, neonLime, cyber, mint, sunset
    var id: String { rawValue }
}

enum FontScale: CGFloat, Codable, CaseIterable {
    case small = 0.85
    case `default` = 1.0
    case large = 1.15
    case xLarge = 1.3
}

enum HardwareNotchMode: String, Codable {
    case auto          // detect via NSScreen.safeAreaInsets
    case forceVirtual  // ignore any hardware notch, draw a virtual overlay
}
```

### 5.2 Store

```swift
@MainActor
final class NotchCustomizationStore: ObservableObject {
    static let shared = NotchCustomizationStore()

    @Published private(set) var customization: NotchCustomization
    @Published var isEditing: Bool = false

    private var editDraftOrigin: NotchCustomization?
    private let defaultsKey = "notchCustomization.v1"

    private init() {
        if let loaded = Self.loadFromDefaults() {
            self.customization = loaded
        } else {
            // No v1 key yet. Migrate from legacy, then write v1 BEFORE
            // removing legacy keys so the migration is idempotent on
            // crash: if writing v1 fails, legacy keys stay intact and
            // next launch retries from scratch.
            self.customization = Self.readLegacyOrDefault()
            if self.saveAndVerify() {
                Self.removeLegacyKeys()
            } else {
                Log.error("[NotchCustomizationStore] Initial v1 write failed; legacy keys retained for retry on next launch")
            }
        }
    }

    func update(_ mutation: (inout NotchCustomization) -> Void) {
        mutation(&customization)
        save()
    }

    func enterEditMode() {
        editDraftOrigin = customization
        isEditing = true
    }

    func commitEdit() {
        editDraftOrigin = nil
        isEditing = false
        save()
    }

    func cancelEdit() {
        if let origin = editDraftOrigin {
            customization = origin
            save()
        }
        editDraftOrigin = nil
        isEditing = false
    }

    @discardableResult
    private func save() -> Bool {
        do {
            let data = try JSONEncoder().encode(customization)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            return true
        } catch {
            Log.error("[NotchCustomizationStore] save failed: \(error)")
            return false
        }
    }

    /// Save and roundtrip-verify by reading back. Used by migration
    /// so we only delete legacy keys after confirming persistence.
    private func saveAndVerify() -> Bool {
        guard save() else { return false }
        return Self.loadFromDefaults() != nil
    }

    private static func loadFromDefaults() -> NotchCustomization? {
        guard let data = UserDefaults.standard.data(forKey: "notchCustomization.v1") else { return nil }
        return try? JSONDecoder().decode(NotchCustomization.self, from: data)
    }

    /// Pull legacy @AppStorage values into a new NotchCustomization
    /// WITHOUT deleting the source keys. Deletion is a separate step
    /// that only runs after the v1 key is successfully written.
    private static func readLegacyOrDefault() -> NotchCustomization {
        var c = NotchCustomization.default
        let d = UserDefaults.standard
        if d.object(forKey: "usePixelCat") != nil {
            c.showBuddy = d.bool(forKey: "usePixelCat")
        }
        // ... any additional legacy keys added here follow the same pattern
        return c
    }

    private static func removeLegacyKeys() {
        UserDefaults.standard.removeObject(forKey: "usePixelCat")
        // ... any additional legacy keys added here follow the same pattern
    }
}
```

Key design choices:

- **Pure value type** for the customization. Codable roundtrip is
  trivial, testing needs no mocks, and any mutation produces a single
  atomic `@Published` notification — no "half-updated theme" frames.
- **`update` closure API** funnels every mutation through one place so
  `save()` is called exactly once per change.
- **Live edit uses a snapshot**, not a diff log. Cancel is a single
  assignment back to the snapshot — no per-field undo.
- **Versioned UserDefaults key** (`notchCustomization.v1`) leaves room
  for future schema migrations via `.v2`, `.v3` etc.
- **Legacy migration is one-shot and destructive.** After the first
  successful save to `v1`, legacy keys (`usePixelCat`) are removed so
  they can't diverge.

### 5.3 Theme module

```swift
struct NotchPalette: Equatable {
    let bg: Color
    let fg: Color
    let secondaryFg: Color
}

extension NotchPalette {
    static func `for`(_ id: NotchThemeID) -> NotchPalette {
        switch id {
        case .classic:  return NotchPalette(bg: .black,               fg: .white,               secondaryFg: Color(white: 1, opacity: 0.4))
        case .paper:    return NotchPalette(bg: .white,               fg: .black,               secondaryFg: Color(white: 0, opacity: 0.55))
        case .neonLime: return NotchPalette(bg: Color(hex: 0xCAFF00), fg: .black,               secondaryFg: Color(white: 0, opacity: 0.55))
        case .cyber:    return NotchPalette(bg: Color(hex: 0x7C3AED), fg: Color(hex: 0xF0ABFC), secondaryFg: Color(hex: 0xC4B5FD))
        case .mint:     return NotchPalette(bg: Color(hex: 0x4ADE80), fg: .black,               secondaryFg: Color(white: 0, opacity: 0.55))
        case .sunset:   return NotchPalette(bg: Color(hex: 0xFB923C), fg: .black,               secondaryFg: Color(white: 0, opacity: 0.5))
        }
    }
}
```

Status colors live in Asset Catalog under `NotchStatus/`:

```
NotchStatus/
  Success.colorset  →  #4ADE80
  Warning.colorset  →  #FB923C
  Error.colorset    →  #F87171
```

Views use `Color("NotchStatus/Success")` etc. These are **not** in the
palette and do not change with theme — they preserve semantic meaning
(approval-needed is always a warning color regardless of theme).

### 5.4 Font scaling

All notch text uses a helper that multiplies the base size by the
current scale:

```swift
extension View {
    func notchFont(_ baseSize: CGFloat, weight: Font.Weight = .medium, design: Font.Design = .monospaced) -> some View {
        self.modifier(NotchFontModifier(baseSize: baseSize, weight: weight, design: design))
    }
}

struct NotchFontModifier: ViewModifier {
    @EnvironmentObject var store: NotchCustomizationStore
    let baseSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: baseSize * store.customization.fontScale.rawValue, weight: weight, design: design))
    }
}
```

All existing `.font(.system(size: N, ...))` calls in the notch tree
are replaced with `.notchFont(N, ...)`. A single grep pass identifies
every call site. Scale changes take effect immediately via the
`@EnvironmentObject` dependency.

**`@EnvironmentObject` in auxiliary windows.** Because
`NotchLiveEditPanel` is a separate `NSWindow`, its content view's
SwiftUI environment does not automatically inherit the
`@EnvironmentObject` injected at the main scene root. The
`NotchLiveEditPanel`'s hosting view must explicitly re-inject the
store:

```swift
let hostingView = NSHostingView(
    rootView: NotchLiveEditOverlay()
        .environmentObject(NotchCustomizationStore.shared)
)
panel.contentView = hostingView
```

Same applies to any future auxiliary SwiftUI window.

### 5.5 Window geometry & hardware-notch detection

**Subscription ownership:** `NotchWindowController` is the sole owner
of the `store.$customization` subscription. It stores a
`Combine.AnyCancellable` as a private property:

```swift
private var customizationCancellable: AnyCancellable?

func attachStore(_ store: NotchCustomizationStore) {
    customizationCancellable = store.$customization
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.applyGeometry() }
}
```

The cancellable is released when `NotchWindowController` deinits —
matching the window lifetime. `WindowManager` owns the
`NotchWindowController` instance and is responsible for calling
`attachStore(...)` once after creation, but `WindowManager` itself
holds no subscription.

**Computation flow (on every customization change):**

```
hasHardwareNotch =
    switch hardwareNotchMode:
        .auto           → NSScreen.main?.safeAreaInsets.top > 0
        .forceVirtual   → false

baseNotchSize = hasHardwareNotch
    ? screen hardware notch dimensions from safeAreaInsets
    : synthetic default size (180pt × 37pt)

runtimeWidth = clamp(measuredContentWidth,
                     minIdleWidth,
                     store.customization.maxWidth)

baseX = (screen.width - runtimeWidth) / 2
clampedOffset = clamp(store.customization.horizontalOffset,
                      -baseX,
                      screen.width - baseX - runtimeWidth)
finalX = baseX + clampedOffset

notchY = screen top (always pinned)
```

**`horizontalOffset` clamp semantics:** the clamp is applied at
render time only — the stored value is never written back. Rationale:
if a user sets offset +300 on a wide external display and later
switches to a 1280pt built-in display where the legal max is +200,
the stored value is silently clamped to +200 for the duration they
use the smaller screen, but restored to +300 when they plug the
external display back in. This is the intentional behavior. The clamp
is stateless; the store is not mutated by render-time math.

**External monitor plug / unplug:** The existing `ScreenObserver`
already subscribes to
`NSApplication.didChangeScreenParametersNotification`. Its handler
now:

1. Calls `notchWindowController.applyGeometry()` to re-detect the
   active screen's notch + re-layout.
2. **If `store.isEditing == true` at the moment of the screen change,
   auto-cancels live edit mode** via `store.cancelEdit()`. This
   tears down the `NotchLiveEditPanel` overlay and reverts any draft
   changes. Rationale: attempting to migrate the overlay to a new
   screen mid-edit is complex and error-prone, and auto-committing
   unconfirmed changes would violate user intent. Auto-cancel is
   the safe default — the user can re-enter live edit mode on the
   new active screen.

### 5.6 New files

```
ClaudeIsland/
  Models/
    NotchCustomization.swift         ← value type, enums
    NotchTheme.swift                  ← palette definitions, NotchThemeID
  Services/State/
    NotchCustomizationStore.swift     ← ObservableObject store
  UI/Helpers/
    NotchFontModifier.swift           ← font scaling helper
    NotchPaletteModifier.swift        ← palette + scoped theme animation
  UI/Views/
    NotchLiveEditPanel.swift          ← auxiliary NSPanel subclass
    NotchLiveEditOverlay.swift        ← SwiftUI controls inside the panel
    NotchLiveEditSimulator.swift      ← rotating simulated content
```

### 5.7 Files modified

- `ClaudeIsland/App/ClaudeIslandApp.swift` — inject
  `NotchCustomizationStore.shared` as an `@EnvironmentObject` at the
  scene root.
- `ClaudeIsland/UI/Views/NotchView.swift` — replace hardcoded colors
  with palette lookups, replace `.font(.system(size:))` with
  `.notchFont(...)`, thread the store through.
- `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` — gate buddy and
  usage bar visibility on `store.customization.showBuddy` /
  `.showUsageBar`.
- `ClaudeIsland/UI/Views/BuddyASCIIView.swift` — use palette `fg`
  instead of hardcoded white; apply `notchFont`.
- `ClaudeIsland/UI/Views/SystemSettingsView.swift` — add the new Notch
  subsection inside the Appearance tab, add the "Customize Size &
  Position…" entry point.
- `ClaudeIsland/Core/WindowManager.swift` and
  `ClaudeIsland/UI/Views/NotchWindowController.swift` — apply geometry
  from the store, subscribe to store changes.
- `ClaudeIsland/Services/ScreenObserver.swift` — reapply geometry on
  screen-change notifications.
- `ClaudeIsland/Assets.xcassets/` — add `NotchStatus/` color set.

## 6. Interaction flow diagrams

### 6.1 Enter edit mode

```
User taps "Customize Size & Position…"
  → SystemSettingsView.onCustomize()
  → store.enterEditMode()                       ← snapshot taken, isEditing = true
  → SystemSettingsWindow.hide()
  → NotchView observes isEditing
  → renders NotchLiveEditOverlay over notch
  → NotchLiveEditSimulator starts rotating fake content
```

### 6.2 Resize via arrow button

```
User clicks ◀
  → NotchLiveEditOverlay.onLeftArrow()
  → store.update { $0.maxWidth = max(minWidth, $0.maxWidth - 2) }
  → save() fires
  → NotchWindowController observes customization change
  → applyGeometry() recalculates and animates frame
```

### 6.3 Cancel

```
User clicks Cancel
  → NotchLiveEditOverlay.onCancel()
  → store.cancelEdit()
  → customization = editDraftOrigin
  → save() fires with original values
  → NotchWindowController applyGeometry() returns to pre-edit
  → SystemSettingsWindow.show() restores Settings
  → NotchLiveEditOverlay disappears (driven by isEditing = false)
```

## 7. Testing strategy

### 7.1 Unit tests

```
ClaudeIslandTests/
  NotchCustomizationTests.swift
    - Codable roundtrip preserves every field
    - Decoding missing fields uses defaults (forward-compat)
    - FontScale rawValue mapping (0.85 / 1.0 / 1.15 / 1.3)
    - All HardwareNotchMode cases decode

  NotchCustomizationStoreTests.swift
    - init reads v1 from UserDefaults when present
    - init migrates from usePixelCat legacy key when v1 missing
    - init returns default when no keys exist
    - update(_:) closure mutates and saves exactly once
    - enterEditMode snapshots draft origin
    - commitEdit clears origin, persists changes
    - cancelEdit restores origin and persists
    - Concurrent update calls do not corrupt state (main-actor isolated)

  NotchThemeTests.swift
    - All 6 NotchThemeID cases produce valid, equatable palettes
    - Palettes do not contain status colors
    - Theme raw strings match their enum case names

  AutoWidthTests.swift
    - clampedWidth ≤ maxWidth for all desiredContentWidth
    - clampedWidth ≥ minIdleWidth for all desiredContentWidth
    - Truncation predicate triggers when content > maxWidth
    - Width responds to store mutations
```

### 7.2 Snapshot tests

**Pre-flight check for the plan:** before writing implementation
tasks, grep the project for an existing snapshot testing dependency
(`swift-snapshot-testing`, `SnapshotTesting`, custom `SnapshotBuddy`).
If none exists, snapshot coverage is descoped to a best-effort
manual QA pass — don't add a test-only dependency as part of this
feature.

If a snapshot library is already present, render these baselines:

- **6 themes at default scale** (6 images) — verifies every palette
  renders without crash and text is readable.
- **Classic theme × 4 font scales** (4 images) — verifies scaling
  doesn't break layout.
- **3 edit-mode states** — resize sub-mode, drag sub-mode, Notch
  Preset marker visible.

**Total: 13 snapshots** (down from a naïve 6×4 = 24 matrix that would
have been expensive to maintain for a palette of 3 colors). The
cross-product is covered by unit tests on palette lookup and scale
application, not by image diffs.

### 7.3 Manual QA checklist

Written to `docs/qa/notch-customization.md`:

- [ ] Enter edit mode → arrow buttons resize symmetrically → Save →
      close & relaunch app → width preserved.
- [ ] Enter edit mode → drag an edge → Cancel → width reverts.
- [ ] Enter edit mode → Notch Preset → width snaps to hardware notch
      width + 20pt → dashed marker flashes for 2s.
- [ ] On a MacBook Air without a hardware notch (or with Hardware
      Notch set to Force Virtual) → Notch Preset button disabled
      with help tooltip.
- [ ] Drag Mode → click → notch flashes → dragging moves horizontally
      only, y locked.
- [ ] Switch between all 6 themes → transition animates ≤ 0.3s,
      no flicker.
- [ ] Change font size to XL → all text (including buddy) scales
      proportionally, no layout breakage.
- [ ] Disable Show Buddy → pet disappears, surrounding layout
      collapses cleanly without gaps.
- [ ] Disable Show Usage Bar → usage bar disappears, idle-state notch
      becomes narrower.
- [ ] Idle state with only icon + time visible → notch auto-shrinks
      tight around content (the screenshot case).
- [ ] Claude sends a very long message → notch expands to configured
      maxWidth, then truncates with ellipsis.
- [ ] Plug in external monitor → notch migrates per Hardware Notch
      Mode setting without restart.

## 8. Migration & rollout

### 8.1 User data migration

On first launch after upgrade:

1. `NotchCustomizationStore.init` checks for `notchCustomization.v1`.
2. If absent, it calls `migrateFromLegacyOrDefault()`:
   - Reads `usePixelCat` → `showBuddy`.
   - Removes `usePixelCat` from UserDefaults.
   - Returns a `NotchCustomization` with defaults for all other
     fields.
3. Saves to `.v1` immediately so the migration is idempotent.

### 8.2 Release

- Single PR against `main` targeting **v1.10.0**.
- Bumped `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- **Before cutting the release**, re-check Apple Developer Programs
  Support case `102860621331`. Two branches:
  - **Case still open (error 7000 unresolved):** v1.10.0 ships as a
    pre-release `v1.10.0-rc1` "signed but not notarized" via
    GitHub Releases, mirroring the v1.9.0-rc1 pattern. Homebrew cask
    in `xmqywx/homebrew-codeisland` is updated with the new version
    + sha256 + the existing postflight `xattr -dr
    com.apple.quarantine` hook stays in place.
  - **Case resolved:** v1.10.0 ships as a regular Release. Homebrew
    cask is updated to the new version + sha256, AND the postflight
    `xattr` hook is removed at the same time.
- README install notice and Homebrew README already cover the
  unnotarized state generically and need no changes.

## 9. Open questions

None. All clarifying questions from the brainstorming session have
been answered and incorporated.

## 10. Appendix: brainstorming decisions trace

| # | Feature | Decision |
|---|---|---|
| Scope | 7 features in one release | Chosen: A (all in one design + implementation) |
| #4 Drag | Drag semantics | B — slide along top edge only (not free-floating) |
| #3 Camera mode | Meaning of "camera mode" | Interpretation 1 — has-notch vs no-notch modes, virtual fallback for no-notch |
| #3 Size UX | Size adjustment surface | Live edit mode in-place on the notch itself, not a separate mockup page |
| #3 Height | Vertical resize? | Not adjustable — height is the visual signature |
| #3 Save semantics | What Save persists | Save max width (auto-width runtime uses it as the ceiling) |
| #3 Simulated content | What edit mode previews | Rotating fake Claude messages (short/medium/long) |
| #3 Notch Preset | On no-notch Macs | Disabled + help tooltip |
| #3 Cancel | Rollback granularity | Snapshot at enter; restore on cancel |
| #5 Themes | Preset count | 6 (Classic, Paper, Neon Lime, Cyber, Mint, Sunset) |
| #5 Transition | Switching animation | 0.3s fade |
| #5 Scope | Status color semantics | Status colors preserved, not overridden by theme |
| #6 Auto-width | Behavior at idle | Shrink to content; expand up to user's saved maxWidth on demand |
| #6 Overflow | When content > maxWidth | Single-line truncation with tail ellipsis |
| #7 Font | Scale vs absolute | Relative scale factor (0.85 / 1.0 / 1.15 / 1.3) |
| #7 UI | Control type | Segmented picker, 4 discrete steps |
| Arch | State management | Centralized `NotchCustomizationStore` (Y), not scattered AppStorage (X), not Redux (Z) |
| Arch | Persistence | Single versioned UserDefaults key (`notchCustomization.v1`) |
| Arch | Refactoring scope | Only notch-related AppStorage; leave notification/codelight/behavior untouched |

## 11. Spec review revisions (round 1)

Issues surfaced by the spec-document-reviewer subagent and resolved
before the spec was approved:

1. **Live edit overlay window model** was unspecified. Now
   Section 4.2 defines `NotchLiveEditPanel`, a new auxiliary
   `NSPanel` subclass with `canBecomeKey = true`, distinct from
   `NotchPanel`, positioned over the notch but sized to the full
   screen width so floating controls can live outside the notch
   bounds.
2. **`HardwareNotchMode` 3-case contradictions.** Simplified from
   `.auto / .forceOn / .forceOff` to `.auto / .forceVirtual`. The
   dropped `.forceOn` case had no user scenario and was creating
   inconsistent semantics. Notch Preset is now unambiguously
   enabled iff effective `hasHardwareNotch == true`.
3. **Simulated content rotation** now specifies `TimelineView`
   driver, view-lifetime scope, pause during active gesture with
   0.8s debounce, and a fixed 5-fixture rotation.
4. **Font scale × auto-width interaction** now explicitly states
   `maxWidth` is sacrosanct — font scale changes can trigger
   truncation but never auto-bump the user's saved max.
5. **Cancel during drag sub-mode** now explicitly defined: Save
   and Cancel work from any sub-mode; `editSubMode` is transient
   and dies with the overlay. A state diagram is included.
6. **Theme switching animation** now scoped to a dedicated
   `NotchPaletteModifier` using `.animation(_:value:)` so color
   transitions do not stack on geometry springs.
7. **`save()` migration idempotency** fixed: `init` writes v1
   before deleting legacy keys, uses a `saveAndVerify()` read-back
   check, and logs on failure. If v1 write fails, legacy keys
   stay untouched and next launch retries.
8. **External monitor disconnect during live edit** now defined:
   `ScreenObserver` auto-cancels live edit mode on screen change,
   tearing down `NotchLiveEditPanel` and reverting the draft.
9. **`horizontalOffset` render-time clamp** now documented as
   intentional: stored value preserved, clamp applied per-render,
   no write-back.
10. **`minIdleWidth`** lowered from 200pt to 140pt to match the
    "tight around content" requirement in QA and justified inline.
11. **`WindowManager` vs `NotchWindowController` subscription
    ownership** now assigned: `NotchWindowController` owns the
    `store.$customization` sink via a private `AnyCancellable`;
    `WindowManager` calls `attachStore(...)` once after creation.
12. **Edit sub-mode state machine** diagram added. Flash animation
    for sub-mode toggle specified concretely (opacity
    `1.0 → 0.4 → 1.0` over 0.3s `.easeInOut`).
13. **`@EnvironmentObject` injection for auxiliary `NSWindow`s**
    documented: the store must be re-injected into the
    `NotchLiveEditPanel`'s hosting view since `@EnvironmentObject`
    does not cross `NSWindow` boundaries.
14. **Snapshot test matrix** reduced from 24 to 13 images and
    made conditional on existing snapshot library detection.
15. **Release section** now has a pre-flight check on Apple case
    `102860621331` with distinct paths for "case still open" vs
    "case resolved".
