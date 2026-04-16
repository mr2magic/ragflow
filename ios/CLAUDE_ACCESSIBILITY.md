# CLAUDE_ACCESSIBILITY.md — Accessibility

## Core Principle

Accessibility is a first-class feature, not an afterthought. Every view must be fully operable with VoiceOver, Switch Control, Voice Control, and keyboard navigation.

---

## Accessibility Modifiers Checklist

```swift
// Every interactive element needs:
Button(action: capturePhoto) {
    Image(systemName: "camera.fill")
}
.accessibilityLabel("Capture photo")           // What it IS
.accessibilityHint("Double-tap to take a photo") // What happens
.accessibilityAddTraits(.isButton)             // Usually inferred for Button
.accessibilityRemoveTraits(.isImage)           // Remove conflicting traits

// Non-interactive decorative elements
Image("decorative-background")
    .accessibilityHidden(true)   // hides from VoiceOver entirely

// Group related elements
HStack {
    Image(systemName: "heart.fill").foregroundStyle(.red)
    Text("128 likes")
}
.accessibilityElement(children: .combine)      // VoiceOver reads as one: "128 likes"
.accessibilityLabel("128 likes")

// Containers with custom navigation
VStack {
    ForEach(items) { ItemRow(item: $0) }
}
.accessibilityElement(children: .contain)      // preserve individual child accessibility
```

---

## Dynamic Type

```swift
// ALWAYS use system font styles — never hardcode point sizes
Text("Title").font(.title)
Text("Body copy").font(.body)
Text("Caption").font(.caption)

// Custom fonts that scale
Text("Heading")
    .font(.custom("SF Pro Display", size: 28, relativeTo: .title))

// Layouts that adapt to larger text sizes
// ❌ Fixed horizontal layout breaks at Accessibility sizes
HStack {
    label
    Spacer()
    value
}

// ✅ Adaptive layout with ViewThatFits
ViewThatFits(in: .horizontal) {
    HStack { label; Spacer(); value }
    VStack(alignment: .leading) { label; value }
}

// Minimum tap target: 44×44 pt
Button("X") { dismiss() }
    .frame(minWidth: 44, minHeight: 44)   // ensure tap target even if visual is smaller
```

---

## VoiceOver Announcements

```swift
// iOS 26 typed AccessibilityNotification API
import Accessibility

// Announce a status change
AccessibilityNotification.Announcement("Photo saved to library").post()

// Move focus to a specific element
AccessibilityNotification.LayoutChanged(nil).post()    // re-announce current focus
AccessibilityNotification.ScreenChanged(nil).post()    // new screen — refocus first element

// Layout changed with focus target
@State private var focusedElement: AccessibilityFocusState<Bool>.Binding?
AccessibilityNotification.LayoutChanged(focusTarget).post()

// Custom announcements with priority
AccessibilityNotification.Announcement("Recording started")
    .post(delay: 0.5)   // slight delay so VoiceOver finishes current speech
```

---

## Custom Accessibility Actions

```swift
ItemRow(item: item)
    .accessibilityLabel(item.title)
    .accessibilityValue(item.isFavorite ? "Favorited" : "Not favorited")
    .accessibilityActions {
        AccessibilityActionKind(.default) { /* primary action */ }
        AccessibilityAction("Toggle favorite") {
            viewModel.toggleFavorite(item)
        }
        AccessibilityAction("Delete") {
            viewModel.delete(item)
        }
        AccessibilityAction("Share") {
            showShareSheet(for: item)
        }
    }
```

---

## Color & Contrast

```swift
// Minimum contrast ratio: 4.5:1 for normal text, 3:1 for large text (WCAG AA)
// Use semantic colors — they adapt to light/dark and Increase Contrast mode

// Always use .primary / .secondary instead of hardcoded colors for text
Text("Important").foregroundStyle(.primary)    // ✅
Text("Important").foregroundStyle(.white)      // ❌ fails on white backgrounds

// Check Increase Contrast setting
@Environment(\.colorSchemeContrast) var contrast
if contrast == .increased {
    // Use higher-contrast alternative
}

// Never rely on color alone to convey information
// ✅ Color + icon + label
HStack {
    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    Text("Completed").foregroundStyle(.green)
}

// ❌ Color only
Circle().fill(isComplete ? .green : .red)   // colorblind users can't distinguish
```

---

## Reduce Motion

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// Conditional animation
withAnimation(reduceMotion ? .none : .spring(duration: 0.4)) {
    isExpanded.toggle()
}

// Prefer cross-fade over slides when motion is reduced
.transition(reduceMotion ? .opacity : .slide)

// Symbol effects — respect reduce motion
Image(systemName: "checkmark.seal.fill")
    .symbolEffect(.bounce, isActive: !reduceMotion && justCompleted)
```

---

## Reduce Transparency

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

// Fall back from glass to solid backgrounds
someView
    .background(reduceTransparency ? Color(.systemBackground) : Material.ultraThinMaterial)
    .glassEffect(reduceTransparency ? GlassEffect.none : .regular)
```

---

## Keyboard & Hardware Input

```swift
// Full keyboard navigation — onKeyPress for custom shortcuts
.onKeyPress(.space) { viewModel.playPause(); return .handled }
.onKeyPress(.escape) { dismiss(); return .handled }

// Focus system for keyboard navigation
@FocusState private var focusedField: Field?
enum Field: Hashable { case username, password }

TextField("Username", text: $username)
    .focused($focusedField, equals: .username)
    .submitLabel(.next)
    .onSubmit { focusedField = .password }

SecureField("Password", text: $password)
    .focused($focusedField, equals: .password)
    .submitLabel(.done)
    .onSubmit { signIn() }
```

---

## Voice Control

```swift
// Voice Control users say "Tap [label]" — so labels must be:
// 1. Unique on screen
// 2. Match visible text (or be predictable)

// For icon-only buttons, provide a clear label
Button { } label: {
    Image(systemName: "ellipsis.circle")
}
.accessibilityLabel("More options")   // "Tap More options" in Voice Control

// Avoid duplicate labels on same screen
// ❌ Three "Delete" buttons → user must say "Tap Delete 1", "Tap Delete 2"
// ✅ "Delete Photo", "Delete Note", "Delete Account"
ForEach(items) { item in
    Button("Delete \(item.title)") { delete(item) }
        .accessibilityLabel("Delete \(item.title)")
}
```

---

## Testing Accessibility

```swift
// 1. Enable VoiceOver in Simulator: Cmd+F5
// 2. Use Accessibility Inspector (Xcode → Open Developer Tool → Accessibility Inspector)
// 3. Run automated a11y audit:
func testAccessibilityAudit() throws {
    let app = XCUIApplication()
    app.launch()
    // XCTest a11y audit (Xcode 15+)
    try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .dynamicType])
}

// 4. Test with largest text size
// Simulator: Settings → Accessibility → Display & Text Size → Larger Text → max
```

---

## Accessibility Checklist Per Feature

Before merging any feature:

- [ ] All interactive elements have `.accessibilityLabel`
- [ ] Meaningful images have labels; decorative images are `.accessibilityHidden(true)`
- [ ] Tab order is logical (top-to-bottom, left-to-right)
- [ ] All text uses Dynamic Type font styles
- [ ] Color is not the only differentiator
- [ ] Animations respect `accessibilityReduceMotion`
- [ ] Minimum tap target 44×44pt on all buttons
- [ ] VoiceOver tested manually on device
- [ ] `performAccessibilityAudit` passes in UI tests

---

*See also: `CLAUDE_SWIFTUI.md` for `ViewThatFits` and adaptive layouts.*
