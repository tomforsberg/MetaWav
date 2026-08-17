import SwiftUI
import AVFoundation

enum ProposedChangeKind: String {
	case trackFile = "Track File"
	case frontArt = "Front Artwork"
	case backArt = "Back Artwork"
	case relatedFile = "Related File"
}

struct ProposedChange: Identifiable, Hashable {
	let id = UUID()
	let kind: ProposedChangeKind
	let albumName: String
	let trackId: UUID? // only for track/related
	let itemName: String // track name or label (Front Artwork / Related display)
	let oldPath: String
	let newURL: URL
}

struct RescanReviewView: View {
    let proposedChanges: [ProposedChange]
    let onAccept: ([ProposedChange]) -> Void
    let onCancel: () -> Void

	@State private var selected: Set<UUID> = []

	var body: some View {
		VStack(spacing: 12) {
			// Header
			HStack {
				Text("Proposed Path Updates")
					.font(.system(size: 16, weight: .bold))
				Spacer()
				Button("Select All") { selected = Set(proposedChanges.map { $0.id }) }
				Button("Select None") { selected.removeAll() }
			}

			// Scrollable list section
			ScrollView {
				VStack(spacing: 8) {
					ForEach(proposedChanges) { change in
						RescanRow(change: change, isSelected: selected.contains(change.id)) {
							if selected.contains(change.id) { selected.remove(change.id) } else { selected.insert(change.id) }
						}
					}
				}
			}
			.frame(maxHeight: .infinity)

			// Footer
			HStack {
				Text("Selected: \(selected.count) of \(proposedChanges.count)")
					.font(.system(size: 12))
					.foregroundColor(.secondary)
				Spacer()
				Button("Cancel") { onCancel() }
				Button("Accept Changes") {
					let accepted = proposedChanges.filter { selected.contains($0.id) }
					onAccept(accepted.isEmpty ? proposedChanges : accepted)
				}
				.keyboardShortcut(.defaultAction)
			}
		}
		.padding(16)
		.onAppear { selected = Set(proposedChanges.map { $0.id }) }
	}
}

private struct RescanRow: View {
	let change: ProposedChange
	let isSelected: Bool
	let toggle: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 8) {
				Button(action: toggle) {
					Image(systemName: isSelected ? "checkmark.square.fill" : "square")
				}
				.buttonStyle(PlainButtonStyle())
				
				VStack(alignment: .leading, spacing: 2) {
					HStack(spacing: 6) {
						Text(change.itemName)
							.font(.system(size: 13, weight: .medium))
						Text("•")
							.foregroundColor(.secondary)
						Text(change.albumName)
							.font(.system(size: 12))
							.foregroundColor(.secondary)
						Spacer()
						Text(change.kind.rawValue)
							.font(.system(size: 11))
							.foregroundColor(.secondary)
					}
					
					Text("Old: \(change.oldPath)")
						.font(.system(size: 11, design: .monospaced))
						.foregroundColor(.secondary)
						.lineLimit(2)
					Text("New: \(change.newURL.path)")
						.font(.system(size: 11, design: .monospaced))
						.foregroundColor(.green)
						.lineLimit(2)
				}
				Spacer()
			}
		}
		.padding(10)
		.background(Color(NSColor.windowBackgroundColor))
		.cornerRadius(6)
		.overlay(
			RoundedRectangle(cornerRadius: 6)
				.stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.3), lineWidth: 1)
		)
	}
}


