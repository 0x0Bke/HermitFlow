//
//  LoginItemController.swift
//  HermitFlow
//

import Foundation
import ServiceManagement

@MainActor
final class LoginItemController {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard SMAppService.mainApp.status != .enabled else {
                return
            }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else {
                return
            }
            try SMAppService.mainApp.unregister()
        }
    }
}
