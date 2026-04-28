import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @StateObject private var auth = AuthService.shared
    @AppStorage("app_theme") private var themeRaw: String = AppTheme.simple.rawValue

    private var isDossier: Bool { themeRaw == AppTheme.dossier.rawValue }

    var body: some View {
        Group {
            if isDossier {
                dossierStyle
            } else {
                simpleStyle
            }
        }
    }

    // MARK: - Dossier style

    private var dossierStyle: some View {
        ZStack {
            DT.manila.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                dossierBrand
                Spacer()
                dossierButtons
                Spacer()
                dossierFooter
            }
            .padding(.horizontal, 32)
        }
    }

    private var dossierBrand: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RAGION")
                .font(DT.mono(11, weight: .bold))
                .tracking(4)
                .foregroundStyle(DT.stamp)
            Text("Sign in to continue")
                .font(DT.serif(28, weight: .semibold))
                .foregroundStyle(DT.ink)
            Text("Where retrieval meets reason")
                .font(DT.serif(15))
                .italic()
                .foregroundStyle(DT.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dossierButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                auth.handleAppleSignIn(result: result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: DT.stampCorner))

            dossierStubButton(label: "Continue with Google",   icon: "globe")
            dossierStubButton(label: "Continue with LinkedIn", icon: "network")
            dossierStubButton(label: "Continue with GitHub",   icon: "chevron.left.forwardslash.chevron.right")

            if let err = auth.authError {
                Text(err)
                    .font(DT.mono(10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }

            #if DEBUG
            Button(action: { auth.bypassForTesting() }) {
                Text("⚠ BYPASS LOGIN (DEBUG)")
                    .font(DT.mono(9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }
            #endif
        }
    }

    private func dossierStubButton(label: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
            Text(label)
                .font(DT.mono(11, weight: .bold))
                .tracking(0.5)
            Spacer()
            Text("COMING SOON")
                .font(DT.mono(8, weight: .bold))
                .tracking(1)
                .foregroundStyle(DT.inkFaint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(DT.inkFaint, lineWidth: 1))
        }
        .foregroundStyle(DT.inkFaint)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DT.card)
        .overlay(RoundedRectangle(cornerRadius: DT.stampCorner).stroke(DT.rule, lineWidth: 1))
        .opacity(0.55)
    }

    private var dossierFooter: some View {
        Text("By signing in you agree to the Terms of Service and Privacy Policy.")
            .font(DT.mono(9))
            .tracking(0.3)
            .foregroundStyle(DT.inkFaint)
            .multilineTextAlignment(.center)
            .padding(.bottom, 16)
    }

    // MARK: - Simple style

    private var simpleStyle: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Ragion")
                    .font(.largeTitle.bold())
                Text("Where retrieval meets reason")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    auth.handleAppleSignIn(result: result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)

                simpleStubButton(label: "Continue with Google")
                simpleStubButton(label: "Continue with LinkedIn")
                simpleStubButton(label: "Continue with GitHub")

                if let err = auth.authError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                #if DEBUG
                Button(action: { auth.bypassForTesting() }) {
                    Text("⚠ Bypass Login (Debug)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
                #endif
            }
            .padding(.horizontal, 24)

            Text("By signing in you agree to our Terms of Service and Privacy Policy.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }

    private func simpleStubButton(label: String) -> some View {
        HStack {
            Text(label)
                .font(.body.weight(.semibold))
            Spacer()
            Text("Coming Soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.secondary)
        .opacity(0.6)
    }
}
