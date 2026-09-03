import SwiftUI

/// Preset creation, activation, editing, and deletion in one coherent panel.
struct PresetsView: View {
    @ObservedObject var bot: TibiaBot

    @State private var selectedPresetId: UUID?
    @State private var newPresetName = ""
    @State private var editingName = ""
    @State private var pendingDeletion: PresetConfig?

    private var selectedPreset: PresetConfig? {
        guard let selectedPresetId else { return nil }
        return bot.presets.first { $0.id == selectedPresetId }
    }

    private var activePreset: PresetConfig? {
        guard let activePresetId = bot.activePresetId else { return nil }
        return bot.presets.first { $0.id == activePresetId }
    }

    var body: some View {
        ScrollView {
            PixelArtPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        TibiaAssetImage(.iconPermissions)
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("PRESETS")
                                .font(Theme.headingFont(size: 15))
                                .foregroundStyle(Theme.textBright)
                            Text("Capture regions and combat settings")
                                .font(Theme.utilityFont())
                                .foregroundStyle(Theme.textDim)
                        }
                    }

                    activePresetBanner

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SAVED PRESETS")
                            .font(Theme.headingFont())
                            .foregroundStyle(Theme.text)

                        if bot.presets.isEmpty {
                            Text("No presets yet. Name the current setup below to save the first one.")
                                .font(Theme.utilityFont())
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 3) {
                                    ForEach(bot.presets) { preset in
                                        PresetRow(
                                            preset: preset,
                                            isSelected: selectedPresetId == preset.id,
                                            isActive: bot.activePresetId == preset.id
                                        ) {
                                            selectedPresetId = preset.id
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 166)
                            .scrollIndicators(.visible)
                        }
                    }

                    Divider()
                        .overlay(Theme.borderMid)

                    if let selectedPreset {
                        selectedPresetEditor(selectedPreset)
                    } else {
                        Text("Select a preset to activate, update, rename, or delete it.")
                            .font(Theme.utilityFont())
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                        .overlay(Theme.borderMid)

                    createPresetRow
                }
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .background {
            TibiaAssetImage(.stoneBackground, resizingMode: .tile)
        }
        .onAppear {
            selectedPresetId = bot.activePresetId ?? bot.presets.first?.id
            updateEditingName(for: selectedPresetId)
        }
        .onChange(of: selectedPresetId) { _, newValue in
            updateEditingName(for: newValue)
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "preset")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete preset", role: .destructive) {
                deletePendingPreset()
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("This removes the saved preset. Your current configuration remains available.")
        }
    }

    private var activePresetBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(activePreset == nil ? Theme.textDim : Theme.success)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text("ACTIVE PRESET")
                    .font(Theme.utilityFont(weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                Text(activePreset?.name ?? "Current configuration")
                    .font(Theme.headingFont())
                    .foregroundStyle(activePreset == nil ? Theme.text : Theme.success)
                    .lineLimit(1)
            }

            Spacer()

            Text(activePreset?.regions.isFullyConfigured == true ? "📍" : "")
                .accessibilityLabel(activePreset?.regions.isFullyConfigured == true ? "Regions configured" : "")
        }
        .padding(6)
        .background(Theme.bg)
        .tibiaFrame(.fieldFrame, insets: EdgeInsets(top: 11, leading: 11, bottom: 11, trailing: 11))
        .overlay {
            Rectangle()
                .strokeBorder(activePreset == nil ? Theme.borderMid : Theme.success.opacity(0.45), lineWidth: 1)
                .padding(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func selectedPresetEditor(_ preset: PresetConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SELECTED PRESET")
                .font(Theme.headingFont())
                .foregroundStyle(Theme.text)

            HStack(spacing: 5) {
                TextField("Preset name", text: $editingName)
                    .font(Theme.utilityFont())
                    .textFieldStyle(TibiaTextFieldStyle())
                    .accessibilityLabel("Preset name")

                PixelButton("Rename", color: Theme.accent, compact: true) {
                    let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                    bot.renamePreset(id: preset.id, name: name)
                    editingName = name
                }
                .disabled(trimmedEditingName.isEmpty || trimmedEditingName == preset.name)
                .help("Rename the selected preset")
            }

            HStack(spacing: 6) {
                PixelButton("Activate", color: Theme.success, fillWidth: true, compact: true) {
                    bot.loadPreset(id: preset.id)
                }
                .disabled(bot.activePresetId == preset.id)
                .help("Load this preset and replace the current configuration")

                PixelButton("Save", color: Theme.gold, fillWidth: true, compact: true) {
                    bot.saveToPreset(id: preset.id)
                }
                .help("Save the current configuration into this preset")

                PixelButton("Delete", color: Theme.error, fillWidth: true, compact: true) {
                    pendingDeletion = preset
                }
                .help("Delete the selected preset")
            }
        }
    }

    private var createPresetRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NEW PRESET")
                .font(Theme.headingFont())
                .foregroundStyle(Theme.text)

            HStack(spacing: 5) {
                TextField("Preset name", text: $newPresetName)
                    .font(Theme.utilityFont())
                    .textFieldStyle(TibiaTextFieldStyle())
                    .accessibilityLabel("New preset name")

                PixelButton("Create", color: Theme.gold, compact: true) {
                    let name = trimmedNewPresetName
                    let id = bot.createPreset(name: name)
                    selectedPresetId = id
                    newPresetName = ""
                }
                .disabled(trimmedNewPresetName.isEmpty)
                .help("Create a preset from the current configuration")
            }
        }
    }

    private var trimmedEditingName: String {
        editingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewPresetName: String {
        newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateEditingName(for id: UUID?) {
        guard let id, let preset = bot.presets.first(where: { $0.id == id }) else {
            editingName = ""
            return
        }
        editingName = preset.name
    }

    private func deletePendingPreset() {
        guard let preset = pendingDeletion else { return }
        bot.deletePreset(id: preset.id)
        pendingDeletion = nil
        selectedPresetId = bot.activePresetId ?? bot.presets.first?.id
    }
}

private struct PresetRow: View {
    let preset: PresetConfig
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(isActive ? Theme.Icons.check : "•")
                    .font(Theme.dataFont(weight: .bold))
                    .foregroundStyle(isActive ? Theme.success : Theme.textDim)
                    .frame(width: 14)

                Text(preset.name)
                    .font(Theme.utilityFont(weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textBright : Theme.text)
                    .lineLimit(1)

                Spacer()

                if preset.regions.isFullyConfigured {
                    Text("📍")
                        .accessibilityLabel("Regions configured")
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 30)
            .background(isSelected ? Theme.bgLight : Theme.bg)
            .tibiaFrame(
                isSelected ? .tabSelectedFrame : .fieldFrame,
                insets: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tacticalFocusRing(cornerRadius: 0)
        .accessibilityLabel(preset.name)
        .accessibilityValue(isActive ? "Active preset" : (isSelected ? "Selected" : "Not selected"))
        .help("Select \(preset.name)")
    }
}
