//
//  Settings.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import Foundation
import RZUtilsSwift

public struct Settings {
    static let service = "flyfun-euro-aip.ro-z.net"
    static let shared = Settings()
    
    
    init(){
        let model = AirportMapViewModel.sample()
        print(model)
    }
}
