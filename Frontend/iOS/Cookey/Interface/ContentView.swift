//
//  ContentView.swift
//  Cookey
//
//  Created by qaq on 26/3/2026.
//

import SwiftUI
import Observation

struct ContentView: View {
    @Bindable var model: SessionUploadModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 88, weight: .ultraLight))
                .foregroundStyle(.primary)
                .padding(.bottom, 36)

            Text("Cookey")
                .font(.system(size: 36, weight: .bold, design: .default))
                .padding(.bottom, 14)

            Text("Scan the QR code shown in your terminal\nto transfer a login session to your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            Spacer()

            Button {
                model.startScan()
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
        .sheet(
            isPresented: Binding(
                get: { model.phase != .idle },
                set: { if !$0 { model.dismissSheet() } }
            )
        ) {
            sheetContent
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .scanning:
            NavigationStack {
                #if os(iOS)
                ScannerView { model.handleURL($0) }
                    .navigationTitle("Scan")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { model.dismissSheet() }
                        }
                    }
                #else
                VStack(spacing: 20) {
                    Image(systemName: "link")
                        .font(.system(size: 52, weight: .light))
                    Text("Open the Cookey link on this device.")
                        .font(.title3.weight(.medium))
                    Text("QR scanning is only available on iPhone and iPad. Open the `cookey://login?...` link directly instead.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Done") { model.dismissSheet() }
                    }
                }
                #endif
            }
        case .browsing(let deepLink):
            InAppBrowserView(deepLink: deepLink) { cookies, origins in
                await model.captureAndUpload(
                    cookies: cookies,
                    origins: origins,
                    deepLink: deepLink
                )
            }
        case .uploading, .done, .failed:
            UploadProgressView(phase: model.phase) {
                model.dismissSheet()
            }
        case .apnOptIn(let deepLink):
            APNConsentView(
                deepLink: deepLink,
                onAccept: {
                    await model.acceptNotificationOptIn(for: deepLink)
                },
                onDecline: {
                    APNPromptStateStore.store(.declined, for: deepLink.serverURL)
                    model.dismissSheet()
                }
            )
        }
    }
}

#Preview {
    ContentView(model: SessionUploadModel(pushCoordinator: nil))
}
