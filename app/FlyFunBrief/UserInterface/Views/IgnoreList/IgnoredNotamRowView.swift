//
//  IgnoredNotamRowView.swift
//  FlyFunBrief
//
//  Row view for displaying an ignored NOTAM entry.
//

import SwiftUI
import CoreData

/// Row view for an ignored NOTAM
struct IgnoredNotamRowView: View {
    let ignoredNotam: CDIgnoredNotam

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // NOTAM ID and expiry
            HStack {
                Text(ignoredNotam.notamId ?? "Unknown")
                    .font(.headline)
                    .foregroundStyle(ignoredNotam.isExpired ? .secondary : .primary)

                Spacer()

                if ignoredNotam.isExpired {
                    Text("Expired")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2))
                        .clipShape(Capsule())
                } else if let expires = ignoredNotam.formattedExpiresAt {
                    Text("Until \(expires)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Summary
            if let summary = ignoredNotam.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Reason if provided
            if let reason = ignoredNotam.reason, !reason.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.quote")
                        .font(.caption2)
                    Text(reason)
                        .font(.caption)
                        .italic()
                }
                .foregroundStyle(.tertiary)
            }

            // Added date
            Text("Added \(ignoredNotam.formattedCreatedAt)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(ignoredNotam.isExpired ? 0.6 : 1.0)
    }
}

// MARK: - Preview

struct IgnoredNotamRowView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.viewContext
        let ignored = CDIgnoredNotam(context: context)
        ignored.id = UUID()
        ignored.notamId = "A1234/24"
        ignored.identityKey = "A1234/24|QMRLC|LFPG"
        ignored.summary = "RWY 09L/27R CLSD DUE MAINTENANCE"
        ignored.reason = "Not relevant for my aircraft"
        ignored.createdAt = Date()
        return List {
            IgnoredNotamRowView(ignoredNotam: ignored)
        }
    }
}
