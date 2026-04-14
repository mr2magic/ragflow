import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MAINTAINER NOTE
//
// When adding or changing features, update the matching page in `onboardingPages`
// below. Each page has a `title`, `subtitle`, and up to four `bullets`.
//
// Version history:
//   0.1.0 — initial 8-page carousel
//   0.3.0 — added Library page; updated Chat (share, auto-naming, multi-KB,
//            sources); updated KB (retrieval settings); merged Agent Tools into
//            Workflows; dropped Jina Reader (not yet implemented); 8 pages total
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Data model

private struct OnboardingPage {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    let bullets: [(icon: String, text: String)]
}

// MARK: - Pages
// Update this array whenever features are added, changed, or removed.

private let onboardingPages: [OnboardingPage] = [

    // ── 1. Welcome ────────────────────────────────────────────────────────────
    .init(
        systemImage: "books.vertical.fill",
        tint: .purple,
        title: "Welcome to RAGFlow",
        subtitle: "Your AI-powered reading companion",
        bullets: [
            ("bubble.left.and.text.bubble.right", "Chat with any document using AI — and get cited answers"),
            ("square.stack.3d.up",                "Organize documents into Knowledge Bases by topic or project"),
            ("cpu",                               "Build multi-step agent workflows with retrieval and LLM steps"),
            ("lock.shield",                       "Runs locally with Ollama, or in the cloud with Claude or OpenAI"),
        ]
    ),

    // ── 2. Knowledge Bases ────────────────────────────────────────────────────
    .init(
        systemImage: "square.stack.3d.up.fill",
        tint: .blue,
        title: "Knowledge Bases",
        subtitle: "Organize and fine-tune your knowledge",
        bullets: [
            ("plus.circle",                       "Tap + to create a new Knowledge Base — the file importer opens automatically"),
            ("rectangle.3.group",                 "Separate KBs keep chats focused: one for research, one for contracts, one per project"),
            ("slider.horizontal.3",               "Long-press any KB → Retrieval Settings to tune Top-K passages, chunk size, and chunking method"),
            ("pencil",                            "Long-press any KB to rename or delete it"),
        ]
    ),

    // ── 3. Import Documents ───────────────────────────────────────────────────
    .init(
        systemImage: "doc.badge.plus",
        tint: .green,
        title: "Import Documents",
        subtitle: "20+ file types — if you can read it, RAGFlow can index it",
        bullets: [
            ("doc.on.doc",                        "Documents: PDF · ePub · Word (DOCX/DOC) · Excel (XLSX/XLS) · PowerPoint (PPTX/PPT) · LibreOffice (ODT/ODS/ODP)"),
            ("text.alignleft",                    "Text & data: TXT · RTF · Markdown · HTML · XML · CSV · TSV · JSON · JSONL · YAML · Email (EML/EMLX)"),
            ("chevron.left.forwardslash.chevron.right", "Code: Swift · Python · JavaScript · TypeScript · Java · C/C++ · Go · SQL · Shell — or paste any web URL"),
            ("arrow.clockwise",                   "Long-press any document → Re-index to re-parse it with updated chunk settings"),
        ]
    ),

    // ── 4. Library & Passages ─────────────────────────────────────────────────
    .init(
        systemImage: "text.book.closed.fill",
        tint: .mint,
        title: "Library & Passages",
        subtitle: "Browse, search, and inspect every indexed chunk",
        bullets: [
            ("magnifyingglass",                   "Search documents by title — use the sort menu to order by date, title, or author"),
            ("checkmark.circle.fill",             "Green badge = indexed; orange badge = no passages found (try re-importing)"),
            ("list.number",                       "Tap any document to open the Passage Viewer: browse every chunk the AI will read"),
            ("arrow.clockwise",                   "Changed chunk settings? Long-press the document and choose Re-index to rebuild it"),
        ]
    ),

    // ── 5. Chat ───────────────────────────────────────────────────────────────
    .init(
        systemImage: "bubble.left.and.text.bubble.right.fill",
        tint: .orange,
        title: "Chat with Your Documents",
        subtitle: "Ask anything — get cited, sourced answers",
        bullets: [
            ("doc.text.magnifyingglass",          "Tap 'N passages used' under any reply to read the exact chunks the AI retrieved"),
            ("plus.circle",                       "Search across multiple KBs in one chat — tap + in the scope bar to add another KB"),
            ("square.and.arrow.up",               "Tap the share button (top-right) to export the full conversation as plain text"),
            ("pencil",                            "Sessions are auto-named from your first message — long-press to rename or delete"),
        ]
    ),

    // ── 6. Agent Workflows ────────────────────────────────────────────────────
    .init(
        systemImage: "cpu",
        tint: .purple,
        title: "Agent Workflows",
        subtitle: "Build multi-step AI pipelines",
        bullets: [
            ("wand.and.stars",                    "Choose from templates: RAG Q&A, Deep Summarizer, Keyword Expander, or Custom"),
            ("square.3.layers.3d",                "Chain steps: Retrieve → Rewrite query → LLM → Answer"),
            ("magnifyingglass.circle",            "Add a Web Search step (requires a free Brave Search API key in Settings)"),
            ("clock.arrow.circlepath",            "Every run is saved — tap History to review and copy past outputs"),
        ]
    ),

    // ── 7. Choose Your AI ─────────────────────────────────────────────────────
    .init(
        systemImage: "gearshape.2.fill",
        tint: .indigo,
        title: "Choose Your AI",
        subtitle: "Claude, OpenAI, or Ollama — you decide",
        bullets: [
            ("sparkles",                          "Claude: paste your Anthropic API key for best-in-class reasoning and long-context understanding"),
            ("wand.and.rays",                     "OpenAI: use GPT-4o or any OpenAI-compatible model with your API key"),
            ("server.rack",                       "Ollama: connect to a local model at localhost or on your network for complete offline privacy"),
            ("key.fill",                          "Your API keys are stored in the iOS Keychain — never transmitted except to the provider's own servers"),
        ]
    ),

    // ── 8. You're All Set! ────────────────────────────────────────────────────
    .init(
        systemImage: "checkmark.seal.fill",
        tint: .green,
        title: "You're All Set!",
        subtitle: "Three steps to your first conversation",
        bullets: [
            ("1.circle.fill",                     "Open Settings (gear icon) and add your API key — or set your Ollama host for local inference"),
            ("2.circle.fill",                     "Tap + to create a Knowledge Base — the file importer opens automatically"),
            ("3.circle.fill",                     "Import documents, wait for indexing to finish, then tap Chats and start asking questions"),
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
