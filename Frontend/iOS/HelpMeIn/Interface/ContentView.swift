//
//  ContentView.swift
//  HelpMeIn
//
//  Created by qaq on 26/3/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 88, weight: .ultraLight))
                .foregroundStyle(.primary)
                .padding(.bottom, 36)

            Text("HelpMeIn")
                .font(.system(size: 36, weight: .bold, design: .default))
                .padding(.bottom, 14)

            Text("Scan the QR code shown in your terminal\nto transfer a login session to your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            Spacer()

            Button {
                showScanner = true
            } label: {
                Text("Scan QR Code")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
        }
        .sheet(isPresented: $showScanner) {
            ScannerPlaceholderView()
        }
    }
}

private struct ScannerPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(.secondary)
                Text("Camera scanner coming soon")
                    .font(.title3.weight(.medium))
                Text("Point your camera at a\n`helpmein login` QR code.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
