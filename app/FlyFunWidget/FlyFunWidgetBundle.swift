//
//  FlyFunWidgetBundle.swift
//  FlyFunWidget
//
//  Widget bundle for Live Activities only.
//

import WidgetKit
import SwiftUI

@main
struct FlyFunWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Only include the Live Activity widget
        FlyFunWidgetLiveActivity()
    }
}
