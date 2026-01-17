//
//  FlyFunWidgetLiveActivity.swift
//  FlyFunWidget
//
//  Live Activity widget - uses OfflineModeActivityAttributes from shared file
//

import ActivityKit
import WidgetKit
import SwiftUI

// This widget uses OfflineModeActivityAttributes and related views
// from OfflineModeActivity.swift which is shared between both targets.

// The FlyFunWidgetLiveActivity widget is defined here to register
// the Live Activity with the widget extension.

struct FlyFunWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OfflineModeActivityAttributes.self) { context in
            // Lock screen/banner UI - uses view from shared file
            HStack {
                ZStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 44, height: 44)
                    Image(systemName: "airplane")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline Mode")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(context.attributes.modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if context.state.isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.blue)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .font(.title2)
                            .foregroundStyle(.white)
                        Text("Offline")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(context.attributes.modelName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text(context.state.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                    } else {
                        Text(context.state.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if let progress = context.state.progress, progress > 0 && progress < 1 {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .padding(.horizontal, 16)
                    }
                }
            } compactLeading: {
                // Keep minimal to hide within Dynamic Island pill
                EmptyView()
            } compactTrailing: {
                // Keep minimal to hide within Dynamic Island pill
                EmptyView()
            } minimal: {
                // Minimal view when space is limited
                EmptyView()
            }
        }
    }
}
