//
//  MapDetailView.swift
//  FlyFunEuroAIP
//
//  Map view with inspector modifier for airport details
//  Inspector shows as trailing sidebar on iPad, sheet on iPhone automatically
//

import SwiftUI
import RZFlight

struct MapDetailView: View {
    @Environment(\.appState) private var state
    @Binding var showingInspector: Bool

    var body: some View {
        AirportMapView()
            .ignoresSafeArea()
            .inspector(isPresented: $showingInspector) {
                AirportInspectorView()
                    .inspectorColumnWidth(min: 300, ideal: 350, max: 400)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    legendMenu
                }
            }
            .overlay(alignment: .topTrailing) {
                // Error banner
                if let error = state?.system.error {
                    ErrorBannerView(error: error) {
                        state?.system.clearError()
                    }
                    .padding()
                }
            }
            .overlay(alignment: .top) {
                // Offline banner
                if state?.system.connectivityMode == .offline && state?.settings.showOfflineBanner == true {
                    OfflineBannerView()
                        .padding(.top, 60)
                }
            }
    }

    // MARK: - Legend Menu

    private var legendMenu: some View {
        Menu {
            Picker("Legend", selection: legendModeBinding) {
                ForEach(LegendMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
        } label: {
            Label("Legend", systemImage: "paintpalette")
        }
    }

    private var legendModeBinding: Binding<LegendMode> {
        Binding(
            get: { state?.airports.legendMode ?? .airportType },
            set: { state?.airports.legendMode = $0 }
        )
    }
}

// MARK: - Error Banner View

private struct ErrorBannerView: View {
    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(error.localizedDescription)
                .font(.caption)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .padding()
        .background(.red.opacity(0.9))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Offline Banner View

private struct OfflineBannerView: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("Offline Mode - Using cached data")
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.9))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }
}

// MARK: - LegendMode Extension

extension LegendMode {
    var systemImage: String {
        switch self {
        case .airportType:
            return "airplane"
        case .procedures:
            return "scope"
        case .runwayLength:
            return "ruler"
        case .notification:
            return "bell"
        case .country:
            return "flag"
        }
    }
}

// MARK: - Preview

#Preview {
    MapDetailView(showingInspector: .constant(false))
}
