//
//  PreviewSamples.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 04/11/2025.
//

import SwiftUI
import FMDB
import RZFlight

extension AirportMapViewModel {
    static func sample() -> AirportMapViewModel {
        guard let url = Bundle.main.url(forResource: "airports_small", withExtension: "db") else {
            return AirportMapViewModel()
        }
        let db = FMDatabase(url: url)
        db.open()
        let knownAirport = KnownAirports(db: db)
        let appModel = AppModel(db: db, knownAirports: knownAirport)
        let model = AirportMapViewModel(appModel: appModel)
        return model
    }
}
