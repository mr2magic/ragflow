import SwiftUI

/// Launch splash shown every cold start.
///
/// First run  → "Get Started" button → OnboardingView → main app
/// Returning  → "Open" button → main app directly
///
/// Wire this as the initial scene in RAGFlowMobileApp; call `onDismiss`
/// to transition to ContentView.
struct SplashView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var showOnboarding = false

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            logoView
                .padding(.bottom, 28)
                .scaleEffect(appeared ? 1 : 0.72)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(duration: 0.55), value: appeared)

            Text("RAGFlow Mobile")
                .font(.largeTitle.bold())
                .padding(.bottom, 8)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                .animation(.spring(duration: 0.45).delay(0.1), value: appeared)

            if !versionString.isEmpty {
                Text("Version \(versionString)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.35).delay(0.2), value: appeared)
            }

            Spacer()

            Button(action: handleTap) {
                Text(hasCompletedOnboarding ? "Open" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.32), value: appeared)
        }
        .onAppear {
            withAnimation { appeared = true }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        // When onboarding marks itself complete (Skip or Get Started on last page),
        // hasCompletedOnboarding flips to true. Detect that here and dismiss + transition.
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                showOnboarding = false
                onDismiss()
            }
        }
    }

    // MARK: - Logo

    @ViewBuilder
    private var logoView: some View {
        if let icon = UIImage(named: "AppIcon") {
            Image(uiImage: icon)
                .resizable()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        } else {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 88))
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Action

    private func handleTap() {
        if hasCompletedOnboarding {
            onDismiss()
        } else {
            showOnboarding = true
        }
    }
}
