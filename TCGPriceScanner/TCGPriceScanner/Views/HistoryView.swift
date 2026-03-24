import SwiftUI

struct HistoryView: View {
    @ObservedObject private var store = ScanHistoryStore.shared
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.entries) { entry in
                            NavigationLink(destination: CardDetailView(card: entry.card)) {
                                HistoryRowView(entry: entry)
                            }
                        }
                        .onDelete { indexSet in
                            store.entries.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.entries.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                    }
                }
            }
            .confirmationDialog("Clear scan history?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    store.clear()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Scans Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Cards you scan will appear here so you can quickly revisit their prices.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
        }
    }
}

struct HistoryRowView: View {
    let entry: ScanHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: entry.card.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.card.game.accentColor.opacity(0.15))
                        .overlay(Text(entry.card.game.icon))
                }
            }
            .frame(width: 40, height: 56)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.card.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(entry.card.game.icon)
                        .font(.caption)
                    if let expansion = entry.card.expansionName {
                        Text(expansion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(entry.scannedAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let trend = entry.card.priceGuide?.trend {
                Text(trend.priceString())
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 2)
    }
}
