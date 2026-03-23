import SwiftUI

// MARK: - Data model

private struct OnboardingPage {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    let bullets: [(icon: String, text: String)]
}

// MARK: - Pages

private let onboardingPages: [OnboardingPage] = [
    .init(
        systemImage: "books.vertical.fill",
        tint: .purple,
        title: "Welcome to RAGFlow",
        subtitle: "Your AI-powered reading companion",
        bullets: [
            ("bubble.left.and.text.bubble.right", "Chat with any book or document using AI"),
            ("square.stack.3d.up",                "Organize documents into Knowledge Bases"),
            ("lock.shield",                        "Runs locally with Ollama, or in the cloud with Claude"),
        ]
    ),
    .init(
        systemImage: "square.stack.3d.up.fill",
        tint: .blue,
        title: "Knowledge Bases",
        subtitle: "Organize your knowledge your way",
        bullets: [
            ("plus.circle",                        "Tap + to create a new Knowledge Base"),
            ("rectangle.3.group",                  "Separate collections keep chats focused and relevant"),
            ("pencil",                             "Long-press any KB to rename or delete it"),
        ]
    ),
    .init(
        systemImage: "doc.badge.plus",
        tint: .green,
        title: "Import Documents",
        subtitle: "PDF, ePub, TXT — from Files or a URL",
        bullets: [
            ("plus",                               "Tap + in the Documents tab to import files"),
            ("doc.richtext",                       "Supports PDF, ePub, and plain-text formats"),
            ("link",                               "Or paste a web URL to import directly from the internet"),
        ]
    ),
    .init(
        systemImage: "bubble.left.and.text.bubble.right.fill",
        tint: .orange,
        title: "Chat with Your Documents",
        subtitle: "Ask anything — get cited answers",
        bullets: [
            ("text.magnifyingglass",               "Relevant passages are retrieved for every question"),
            ("doc.text.magnifyingglass",           "Tap 'N passages used' under any reply to see the exact text passages"),
            ("stop.circle",                        "Hit the stop button to cancel a response mid-stream"),
        ]
    ),
    .init(
        systemImage: "globe.americas.fill",
        tint: .teal,
        title: "Agent Tools",
        subtitle: "Go beyond your documents",
        bullets: [
            ("magnifyingglass",                    "Brave Search pulls live web results into your answer"),
            ("link",                               "Jina Reader extracts clean text from any URL you paste"),
            ("key.fill",                           "Add your Brave API key in Settings → Agent Tools"),
        ]
    ),
    .init(
        systemImage: "gearshape.2.fill",
        tint: .indigo,
        title: "Choose Your AI",
        subtitle: "Claude or Ollama — you decide",
        bullets: [
            ("sparkles",                           "Claude: paste your Anthropic API key to get started"),
            ("server.rack",                        "Ollama: connect to a local model for complete privacy"),
            ("brain",                              "Ollama also powers semantic embeddings for smarter search"),
        ]
    ),
    .init(
        systemImage: "checkmark.seal.fill",
        tint: .green,
        title: "You're All Set!",
        subtitle: "Three steps to your first conversation",
        bullets: [
            ("1.circle.fill",                      "Open Settings (gear icon) and add your API key"),
            ("2.circle.fill",                      "Tap + to create a Knowledge Base"),
            ("3.circle.fill",                      "Import a book and start asking questions"),
        ]
    ),
]

// MARK: - Main view

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompleted = false
    @State private var currentPage = 0

    var body: some View {
        ZStack(alignment: .top) {
            // Paged content
            TabView(selection: $currentPage) {
                ForEach(onboardingPages.indices, id: \.self) { i in
                    OnboardingPageView(page: onboardingPages[i])
                        .tag(i)
                        .padding(.bottom, 140) // clear bottom controls
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Skip button — top right, hidden on last page
            if currentPage < onboardingPages.count - 1 {
                HStack {
                    Spacer()
                    Button("Skip") {
                        withAnimation { hasCompleted = true }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomControls
        }
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Page indicator dots
            HStack(spacing: 8) {
                ForEach(onboardingPages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage
                              ? onboardingPages[currentPage].tint
                              : Color.secondary.opacity(0.3))
                        .frame(width: i == currentPage ? 20 : 8, height: 8)
                        .animation(.spring(duration: 0.3), value: currentPage)
                }
            }

            // Primary action button
            Button(action: advance) {
                Text(currentPage == onboardingPages.count - 1 ? "Get Started" : "Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(onboardingPages[currentPage].tint, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func advance() {
        if currentPage < onboardingPages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { currentPage += 1 }
        } else {
            withAnimation { hasCompleted = true }
        }
    }
}

// MARK: - Single page view

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Icon
                Image(systemName: page.systemImage)
                    .font(.system(size: 88))
                    .foregroundStyle(page.tint)
                    .padding(.bottom, 36)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)

                // Title
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                // Subtitle
                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                // Bullet points
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(page.bullets.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: page.bullets[i].icon)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(page.tint)
                                .frame(width: 24, alignment: .center)

                            Text(page.bullets[i].text)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(
                            .spring(duration: 0.4).delay(0.15 + Double(i) * 0.1),
                            value: appeared
                        )
                    }
                }
                .padding(.horizontal, 36)

                Spacer(minLength: 40)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            withAnimation(.spring(duration: 0.5)) { appeared = true }
        }
        .onDisappear { appeared = false }
    }
}
