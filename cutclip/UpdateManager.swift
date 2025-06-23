//
//  UpdateManager.swift
//  cutclip
//
//  Created by Moinul Moin on 6/23/25.
//

import Foundation
import Sparkle

@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    private let updaterController: SPUStandardUpdaterController
    
    private init() {
        // TODO: Enable auto-updates in v1.1
        updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}