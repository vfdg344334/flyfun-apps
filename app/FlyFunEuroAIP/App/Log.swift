//
//  Log.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import Foundation
import OSLog
import RZUtilsSwift

extension Logger {
    public static let app = RZLogger(subsystem: Bundle.main.bundleIdentifier!, category: "app")
    public static let ui = RZLogger(subsystem: Bundle.main.bundleIdentifier!, category: "ui")
    public static let sync = RZLogger(subsystem: Bundle.main.bundleIdentifier!, category: "sync")
    public static let net = RZLogger(subsystem: Bundle.main.bundleIdentifier!, category: "net")
}

