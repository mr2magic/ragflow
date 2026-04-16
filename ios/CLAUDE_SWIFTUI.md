# CLAUDE_SWIFTUI.md — SwiftUI 6 & iOS 26 UI

## iOS 26 Visual Language: Liquid Glass

iOS 26 introduces **Liquid Glass** — a translucent, refractive material that unifies system UI. All apps must adapt.

### Core Liquid Glass APIs

```swift
// Apply glass background to any view
someView
    .glassEffect()                          // default glass
    .glassEffect(.regular.tinted(.blue))    // tinted variant
    .glassEffect(.thin)                     // thin/overlay variant

// GlassEffectContainer — batches glass rendering for performance
// Wrap multiple glass views that overlap or scroll together
GlassEffectContainer {
    VStack {
        GlassCard(title: "Heart Rate", value: "72 bpm")
        GlassCard(title: "Steps", value: "8,421")
    }
}

// Tab bars and toolbars are glass by default in iOS 26
// To control background visibility:
.toolbarBackgroundVisibility(.visible, for: .navigationBar)
.toolbarBackgroundVisibility(.hidden, for: .tabBar)   // reveal glass underneath
```

### Glass-Aware Color Usage

```swift
// Use semantic colors — they adapt to glass contexts
Text("Label").foregroundStyle(.primary)          // ✅
Text("Label").foregroundStyle(Color.white)        // ❌ breaks on light backgrounds

// Vibrancy for text on glass
Text("Subtitle")
    .foregroundStyle(.secondary)
    .glassEffect()   // system applies vibrancy automatically

// Custom tints
.tint(.accentColor)   // inherit from app accent
```

---

## SwiftUI 6 Essentials

### @Observable in Views

```swift
// View receives @Observable viewmodel — no @StateObject/@ObservedObject
struct ItemListView: View {
    @State private var viewModel = ItemListViewModel()
    // OR inject from parent:
    var viewModel: ItemListViewModel   // passed by reference, changes propagate

    var body: some View {
        List(viewModel.items) { item in
            ItemRow(item: item)
        }
        .task { await viewModel.loadItems() }
        .refreshable { await viewModel.loadItems() }
    }
}
```

### New iOS 26 View Modifiers

```swift
// Mesh gradient backgrounds (iOS 17+, improved in 26)
MeshGradient(
    width: 3, height: 3,
    points: [ /* 9 SIMD2<Float> control points */ ],
    colors: [ /* 9 Colors */ ]
)

// Scroll transitions
ScrollView {
    ForEach(items) { item in
        ItemCard(item: item)
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.5)
                    .scaleEffect(phase.isIdentity ? 1 : 0.95)
            }
    }
}

// Symbol effects (SF Symbols 6)
Image(systemName: "heart.fill")
    .symbolEffect(.bounce, value: isFavorite)
    .symbolEffect(.variableColor.iterative, isActive: isLoading)

// Container-relative frame
someView
    .containerRelativeFrame(.horizontal, count: 3, spacing: 16)

// Typed text selection
Text(verbatim: "Copy me")
    .textSelection(.enabled)
```

### TabView in iOS 26

```swift
// iOS 26: TabView with expanded/collapsed sidebar on iPad, glass tab bar on iPhone
TabView {
    Tab("Home", systemImage: "house.fill") {
        HomeView()
    }
    Tab("Camera", systemImage: "camera.fill") {
        CameraView()
    }
    Tab("Library", systemImage: "photo.stack.fill") {
        LibraryView()
    }
    Tab("Settings", systemImage: "gearshape.fill", role: .search) {
        SettingsView()
    }
}
.tabViewStyle(.sidebarAdaptable)  // sidebar on iPad, tab bar on iPhone
```

### NavigationSplitView for iPad / Mac

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    SidebarView()
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
} content: {
    ItemListView()
} detail: {
    ItemDetailView()
}
.navigationSplitViewStyle(.balanced)
```

---

## SF Symbols 6 Best Practices

```swift
// Always use Image(systemName:) with semantic labels
Image(systemName: "camera.aperture")
    .accessibilityLabel("Camera")
    .imageScale(.large)
    .symbolRenderingMode(.hierarchical)
    .foregroundStyle(.tint)

// Variable value symbols (sensor readings, signal strength)
Image(systemName: "wifi", variableValue: signalStrength)   // 0.0–1.0

// Animated transitions
Image(systemName: isRecording ? "record.circle.fill" : "circle")
    .contentTransition(.symbolEffect(.replace))
```

---

## Animations: iOS 26 Spring & Keyframe

```swift
// Preferred: spring animations
withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
    isExpanded.toggle()
}

// Keyframe animator for multi-property sequences
KeyframeAnimator(initialValue: CardState()) { value in
    CardView()
        .scaleEffect(value.scale)
        .offset(y: value.offsetY)
        .opacity(value.opacity)
} keyframes: { _ in
    KeyframeTrack(\.scale) {
        SpringKeyframe(1.1, duration: 0.2)
        SpringKeyframe(1.0, duration: 0.3)
    }
    KeyframeTrack(\.offsetY) {
        LinearKeyframe(-20, duration: 0.2)
        SpringKeyframe(0, duration: 0.3)
    }
}

// Phase animator for repeating sequences
PhaseAnimator([false, true]) { phase in
    Circle().scaleEffect(phase ? 1.2 : 1.0)
} animation: { phase in
    phase ? .spring(duration: 0.5) : .easeOut(duration: 0.3)
}
```

---

## Custom Layout

```swift
// Use Layout protocol for non-standard arrangements
struct RadialLayout: Layout {
    var radius: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 200, height: proposal.height ?? 200)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let angle = (2 * .pi) / Double(subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.midX + radius * cos(Double(index) * angle)
            let y = bounds.midY + radius * sin(Double(index) * angle)
            subview.place(at: CGPoint(x: x, y: y), anchor: .center, proposal: .unspecified)
        }
    }
}
```

---

## Canvas & Graphics

```swift
// Canvas for high-performance custom drawing (replaces drawRect)
Canvas { context, size in
    let path = Path(ellipseIn: CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10))
    context.fill(path, with: .color(.blue.opacity(0.5)))
    context.stroke(path, with: .color(.blue), lineWidth: 2)

    // Draw resolved symbols
    let symbol = context.resolveSymbol(id: "heartIcon")!
    context.draw(symbol, at: CGPoint(x: size.width / 2, y: size.height / 2))
} symbols: {
    Image(systemName: "heart.fill")
        .tag("heartIcon")
        .foregroundStyle(.red)
}
.drawingGroup()   // rasterize to Metal texture for performance
```

---

## Safe Area & Device Adaptation

```swift
// Always respect safe areas — never hardcode insets
.padding(.bottom, safeAreaInset.bottom)

// Detect device type
#if os(iOS)
    let isIpad = UIDevice.current.userInterfaceIdiom == .pad
#endif

// Dynamic Island awareness — use .statusBarHidden(false) + .persistentSystemOverlays(.visible)
// For Live Activities near the notch:
.widgetAccentable()
.invalidatableContent()

// Bottom sheet with iOS 16+ presentationDetents (still current)
.sheet(isPresented: $showSheet) {
    SheetContent()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationBackground(.regularMaterial)  // glass material
}
```

---

## Previews in iOS 26

```swift
#Preview("Light Mode", traits: .sizeThatFitsLayout) {
    ItemListView(viewModel: ItemListViewModel(repository: MockItemRepository()))
        .preferredColorScheme(.light)
}

#Preview("Dark Glass", traits: .sizeThatFitsLayout) {
    ItemListView(viewModel: ItemListViewModel(repository: MockItemRepository()))
        .preferredColorScheme(.dark)
}

// Preview with environment
#Preview {
    ContentView()
        .environment(AppEnvironment.preview)
}
```

---

*See also: `CLAUDE_ACCESSIBILITY.md` for VoiceOver/Dynamic Type, `CLAUDE_PERFORMANCE.md` for GPU/Metal tips.*
