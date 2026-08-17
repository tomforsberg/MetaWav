import SwiftUI
import AppKit
import AVFoundation

// MARK: - Models

enum PluginType: String, CaseIterable, Identifiable {
	case all = "All"
	case audioFX = "Audio FX"
	case instruments = "Instruments"
	case visualizers = "Visualizers"
	case utilities = "Utilities"

	var id: String { rawValue }
}

struct Plugin: Identifiable, Hashable {
	let id = UUID()
	let name: String
	let description: String
	let developer: String
    let formats: [String] // e.g., ["AU", "VST3"]
	let iconSystemName: String // e.g., "puzzlepiece.fill"
	let version: String
	let bundleIdOrPath: String
	let componentSubType: UInt32
	let compatibility: String // sample rates, host requirements, etc.
    let type: PluginType
	var isEnabled: Bool
}

// MARK: - View Model

final class PluginLibrary: ObservableObject {
    @Published var allPlugins: [Plugin] = []
	@Published var searchText: String = ""
	@Published var selection: Set<Plugin> = []
	@Published var focusedSelection: Plugin? = nil

    init() { refreshFromSystemAUs() }

	var filteredPlugins: [Plugin] {
		let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { return allPlugins }
		let needle = q.lowercased()
		return allPlugins.filter { plugin in
			plugin.name.lowercased().contains(needle) ||
			plugin.description.lowercased().contains(needle) ||
			plugin.developer.lowercased().contains(needle) ||
			plugin.formats.joined(separator: " ").lowercased().contains(needle)
		}
	}

	func refreshFromSystemAUs() {
		let manager = AVAudioUnitComponentManager.shared()
		let all = manager.components(matching: NSPredicate(value: true))
		let effects = all.filter { $0.audioComponentDescription.componentType == kAudioUnitType_Effect }
		self.allPlugins = effects.map { comp in
			let bundlePath: String = comp.iconURL?.deletingLastPathComponent().path ?? ""
			return Plugin(
				name: comp.name,
                description: comp.localizedTypeName,
				developer: comp.manufacturerName,
				formats: ["AU"],
				iconSystemName: "puzzlepiece.fill",
                version: comp.versionString,
				bundleIdOrPath: bundlePath,
				componentSubType: comp.audioComponentDescription.componentSubType,
				compatibility: "Host: AVAudioEngine • macOS",
				type: .audioFX,
				isEnabled: false
			)
		}
	}
}

// MARK: - Main View

struct AddPluginView: View {
	@StateObject private var library = PluginLibrary()

    var body: some View {
		VStack(spacing: 8) {
			HStack(spacing: 12) {
            PluginBrowserView(
                plugins: library.filteredPlugins,
                selection: $library.selection,
                searchText: $library.searchText,
                focusedSelection: $library.focusedSelection,
					onAddSelected: addSelected,
					onRescan: { library.refreshFromSystemAUs() }
            )
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            PluginPreviewPanel(
                plugin: library.focusedSelection,
                onOpenInFinder: openInFinder,
                onRemove: removePlugin
            )
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .tint(Color(red: 0, green: 0.75, blue: 0.39))
        .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
		.onAppear {
            library.refreshFromSystemAUs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mwPluginsDidChange)) { _ in
                library.refreshFromSystemAUs()
        }
    }

    private func addSelected() {
        let selected = library.selection
        let manager = AVAudioUnitComponentManager.shared()
        let all = manager.components(matching: NSPredicate(value: true))
        for p in selected {
            if let comp = all.first(where: { comp in
                comp.audioComponentDescription.componentSubType == p.componentSubType &&
                comp.audioComponentDescription.componentType == kAudioUnitType_Effect
            }) {
                UnifiedAudioEngine.shared.loadEffect(component: comp, completion: nil)
            }
        }
        library.selection.removeAll()
        MenuBarManager.shared.closeAddPluginWindow()
    }

    private func openInFinder(_ plugin: Plugin) {
		#if os(macOS)
		let path = plugin.bundleIdOrPath
		if !path.isEmpty {
			let url = URL(fileURLWithPath: path)
			NSWorkspace.shared.activateFileViewerSelecting([url])
		}
		#endif
	}

    private func removePlugin(_ plugin: Plugin) {
		library.allPlugins.removeAll { $0.id == plugin.id }
		if library.focusedSelection?.id == plugin.id {
			library.focusedSelection = nil
		}
		library.selection.remove(plugin)
    }
}

// Sidebar removed per design update

// MARK: - Browser (search + grid + add button)

struct PluginBrowserView: View {
    let plugins: [Plugin]
	@Binding var selection: Set<Plugin>
	@Binding var searchText: String
	@Binding var focusedSelection: Plugin?
	let onAddSelected: ()->Void
	let onRescan: ()->Void

	@State private var hovered: Plugin.ID?
    @State private var expandedVendors: Set<String> = []

    // Grouped by vendor (developer)
    private var groupedByVendor: [(vendor: String, items: [Plugin])] {
        let groups = Dictionary(grouping: plugins, by: { $0.developer })
        return groups.keys.sorted().map { key in (vendor: key, items: groups[key]!.sorted { $0.name < $1.name }) }
    }

	var body: some View {
		ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 10) {
				HStack(spacing: 8) {
					SearchField(text: $searchText)
					Button {
						onRescan()
					} label: {
						Label("Rescan", systemImage: "arrow.clockwise")
					}
					.buttonStyle(.bordered)
				}
				.padding(.horizontal, 12)
				.padding(.top, 10)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(groupedByVendor, id: \.vendor) { group in
                            DisclosureGroup(isExpanded: bindingForVendor(group.vendor)) {
                                VStack(spacing: 8) {
                                    ForEach(group.items) { plugin in
                                        PluginRow(
                                            plugin: binding(for: plugin),
                                            isSelected: selection.contains(plugin),
                                            isHovered: hovered == plugin.id
                                        )
                                        .onTapGesture {
                                            toggleSelection(plugin)
                                            focusedSelection = plugin
                                        }
                                        .onHover { isHovering in
                                            withAnimation(.easeInOut(duration: 0.18)) {
                                                hovered = isHovering ? plugin.id : nil
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "building.2")
                                        .foregroundColor(Color(white: 0.7))
                                    Text(group.vendor)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(group.items.count)")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color(white: 0.6))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .secondaryGlass(cornerRadius: 8)
                            }
                            .background(Color.clear)
                        }
                    }
                    .padding(12)
                }
				.overlay(alignment: .top) {
					Rectangle().fill(Color.white.opacity(0.03)).frame(height: 0.5)
				}
			}
            .background(glassyPanel)

            Button {
                onAddSelected()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("Add Selected")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(red: 0, green: 0.75, blue: 0.39))
                )
                .foregroundColor(.black)
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            }
			.buttonStyle(.plain)
			.padding(16)
			.opacity(selection.isEmpty ? 0.5 : 1.0)
			.disabled(selection.isEmpty)
		}
	}

    private var glassyPanel: some View {
        ZStack { Color.clear }
            .background(.ultraThinMaterial)
    }

	private func binding(for plugin: Plugin) -> Binding<Plugin> {
		.constant(plugin)
	}

    private func bindingForVendor(_ vendor: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { expandedVendors.contains(vendor) },
            set: { isExpanded in
                if isExpanded {
                    expandedVendors.insert(vendor)
                } else {
                    expandedVendors.remove(vendor)
                }
            }
        )
    }

	private func toggleSelection(_ plugin: Plugin) {
		if selection.contains(plugin) {
			selection.remove(plugin)
		} else {
			selection.insert(plugin)
		}
	}
}

// MARK: - Plugin Card

struct PluginCard: View {
	@Binding var plugin: Plugin
	let isSelected: Bool
	let isHovered: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .center, spacing: 12) {
				ZStack {
					RoundedRectangle(cornerRadius: 12)
						.fill(LinearGradient(
							colors: [Color(.sRGB, white: 0.22, opacity: 1),
									 Color(.sRGB, white: 0.14, opacity: 1)],
							startPoint: .topLeading, endPoint: .bottomTrailing
						))
						.overlay {
							RoundedRectangle(cornerRadius: 12)
								.stroke(Color.white.opacity(0.08), lineWidth: 1)
						}
						.frame(width: 48, height: 48)

					Image(systemName: plugin.iconSystemName)
						.font(.system(size: 22, weight: .regular))
						.foregroundStyle(.white.opacity(0.9))
						.shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 3)
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(plugin.name)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)

					Text(plugin.developer)
						.font(.system(size: 12, weight: .regular))
						.foregroundStyle(.white.opacity(0.65))
						.lineLimit(1)
				}

				Spacer()

				Toggle("", isOn: .constant(plugin.isEnabled))
					.toggleStyle(.switch)
					.labelsHidden()
					.disabled(true)
			}

			Text(plugin.description)
				.font(.system(size: 12))
				.foregroundStyle(.white.opacity(0.8))
				.lineLimit(3)

			HStack(spacing: 6) {
				ForEach(plugin.formats, id: \.self) { tag in
					TagCapsule(text: tag)
				}
				Spacer()
			}
		}
		.padding(12)
		.background(cardBackground)
		.overlay {
			RoundedRectangle(cornerRadius: 14)
				.stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
		}
		.clipShape(RoundedRectangle(cornerRadius: 14))
		.shadow(color: Color.black.opacity(isHovered ? 0.45 : 0.25),
				radius: isHovered ? 20 : 10, x: 0, y: isHovered ? 14 : 8)
		.scaleEffect(isHovered ? 1.01 : 1.0)
		.animation(.easeInOut(duration: 0.18), value: isHovered)
		.animation(.easeInOut(duration: 0.18), value: isSelected)
	}

	private var cardBackground: some View {
		LinearGradient(
			colors: [
				Color(.sRGB, white: 0.16, opacity: 0.95),
				Color(.sRGB, white: 0.10, opacity: 0.95)
			],
			startPoint: .topLeading, endPoint: .bottomTrailing
		)
		.overlay {
			LinearGradient(colors: [Color.white.opacity(0.06), .clear],
						   startPoint: .topLeading, endPoint: .center)
		}
	}

	private var borderColor: Color {
		isSelected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.07)
	}
}

// Compact row for grouped list
private struct PluginRow: View {
    @Binding var plugin: Plugin
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plugin.iconSystemName)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("AU • \(plugin.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(plugin.formats, id: \.self) { tag in
                    TagCapsule(text: tag)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    Color.clear.selectedGlass(cornerRadius: 10)
                } else if isHovered {
                    Color.clear.secondaryGlass(cornerRadius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.clear)
                }
            }
        )
        .overlay(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
            }
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.30 : 0.12), radius: isHovered ? 10 : 4, x: 0, y: isHovered ? 6 : 3)
        .offset(x: isHovered ? 4 : 0)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
    }
}

// MARK: - Preview Panel (Detail)

struct PluginPreviewPanel: View {
	let plugin: Plugin?
	let onOpenInFinder: (Plugin) -> Void
	let onRemove: (Plugin) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			if let plugin {
					HStack(alignment: .center, spacing: 14) {
						RoundedRectangle(cornerRadius: 16)
							.fill(Color.clear)
							.frame(width: 72, height: 72)
							.secondaryGlass(cornerRadius: 16)
							.overlay {
								Image(systemName: plugin.iconSystemName)
									.font(.system(size: 34, weight: .regular))
									.foregroundStyle(.white)
							}

					VStack(alignment: .leading, spacing: 4) {
						Text(plugin.name)
							.font(.system(size: 18, weight: .semibold))
							.foregroundStyle(.white)
						Text(plugin.developer)
							.font(.system(size: 13))
							.foregroundStyle(.white.opacity(0.7))
					}

					Spacer()
				}
				.padding(.bottom, 4)

				infoRow(title: "Version", value: plugin.version, systemImage: "number")
				infoRow(title: "Formats", value: plugin.formats.joined(separator: " •"), systemImage: "square.stack.3d.down.right")
				infoRow(title: "Bundle/Path", value: plugin.bundleIdOrPath, systemImage: "shippingbox")
				infoRow(title: "Compatibility", value: plugin.compatibility, systemImage: "info.circle")

				Spacer()

				HStack(spacing: 10) {
					Button {
						onOpenInFinder(plugin)
					} label: {
						Label("Open in Finder", systemImage: "folder")
					}
					.buttonStyle(.bordered)

					Button(role: .destructive) {
						onRemove(plugin)
					} label: {
						Label("Remove", systemImage: "trash")
					}
					.buttonStyle(.borderedProminent)
				}
			} else {
				VStack(spacing: 10) {
					Image(systemName: "puzzlepiece.extension")
						.font(.system(size: 46))
						.foregroundStyle(.white.opacity(0.8))
					Text("Select a plugin to preview details")
						.font(.system(size: 14))
						.foregroundStyle(.white.opacity(0.7))
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
		}
				.padding(16)
				.glassFill(.ultraThinMaterial)
	}

    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(Color(white: 0.7))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.8))
            Spacer()
        }
    }

    private var detailBackground: some View { Color.clear }
}

// MARK: - Search Field

struct SearchField: View {
	@Binding var text: String

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.foregroundStyle(.white.opacity(0.75))
			TextField("Search plugins…", text: $text)
				.textFieldStyle(.plain)
				.foregroundStyle(.white)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(
			RoundedRectangle(cornerRadius: 10)
				.fill(Color(.sRGB, white: 0.2, opacity: 0.6))
				.overlay {
					RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07), lineWidth: 1)
				}
		)
	}
}

// MARK: - Tag Capsule

struct TagCapsule: View {
	let text: String
	var body: some View {
		Text(text.uppercased())
			.font(.system(size: 10, weight: .semibold, design: .rounded))
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(
				Capsule()
					.fill(LinearGradient(
						colors: [Color(.sRGB, red: 0.24, green: 0.28, blue: 0.32, opacity: 1),
								 Color(.sRGB, red: 0.18, green: 0.20, blue: 0.24, opacity: 1)],
						startPoint: .top, endPoint: .bottom
					))
					.overlay { Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1) }
			)
			.foregroundStyle(.white.opacity(0.85))
	}
}

// MARK: - Preview

struct AddPluginView_Previews: PreviewProvider {
	static var previews: some View {
		AddPluginView()
			.frame(minWidth: 1000, minHeight: 600)
			.preferredColorScheme(.dark)
	}
}


