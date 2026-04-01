//
//  main.swift
//  Cookey
//
//  Created by qaq on 26/3/2026.
//

import Observation
import SwiftUI
#if os(iOS)
    import UIKit
#endif

struct Cookey: App {
    #if os(iOS)
        @UIApplicationDelegateAdaptor(CookeyAppDelegate.self) private var appDelegate
    #endif
    @State private var pushCoordinator: PushRegistrationCoordinator
    @State private var sessionModel: SessionUploadModel

    init() {
        let coordinator = PushRegistrationCoordinator()
        _pushCoordinator = State(initialValue: coordinator)
        _sessionModel = State(initialValue: SessionUploadModel(pushCoordinator: coordinator))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: sessionModel)
                .onOpenURL { sessionModel.handleURL($0) }
                .task {
                    await pushCoordinator.attach(to: sessionModel)
                    #if os(iOS)
                        appDelegate.pushCoordinator = pushCoordinator
                    #endif
                }
        }
    }
}

Cookey.main()
