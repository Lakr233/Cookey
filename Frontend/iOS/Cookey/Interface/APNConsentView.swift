import SwiftUI

struct APNConsentView: View {
    let deepLink: DeepLink
    let onAccept: () async -> Void
    let onDecline: () -> Void

    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(.primary)

            Text("Enable login notifications?")
                .font(.title3.weight(.semibold))

            Text("Cookey can send future login requests from \(deepLink.serverURL.host(percentEncoded: false) ?? deepLink.serverURL.absoluteString) directly to this device.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer()

            Button {
                isSubmitting = true
                Task {
                    await onAccept()
                    isSubmitting = false
                }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Enable Notifications")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSubmitting)
            .padding(.horizontal, 28)

            Button("Not Now", action: onDecline)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSubmitting)
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
        }
    }
}
