//
//  ContentView.swift
//  FlyFunEuroAIP
//
//  Root view that branches between iPhone and iPad layouts.
//  - iPhone (compact): Map-centric with overlays (iPhoneLayoutView)
//  - iPad (regular): NavigationSplitView with sidebar (iPadLayoutView)
//

import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            iPhoneLayoutView()
        } else {
            iPadLayoutView()
        }
    }
}

// MARK: - Preview

#Preview("iPad") {
    ContentView()
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("iPhone") {
    ContentView()
        .environment(\.horizontalSizeClass, .compact)
}
