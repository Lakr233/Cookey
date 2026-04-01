import SwiftUI

struct UploadProgressView: View {
    let phase: SessionUploadModel.Phase
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            switch phase {
            case .uploading:
                ProgressView()
                    .controlSize(.large)
                Text("Uploading session")
                    .font(.title3.weight(.semibold))
                Text("Cookey is encrypting your browser session and sending it back to the terminal.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Transfer complete")
                    .font(.title3.weight(.semibold))
                Text("Your terminal can export the session now.")
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("Transfer failed")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            default:
                EmptyView()
            }

            Spacer()

            if phase != .uploading {
                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)
            }
        }
    }
}
