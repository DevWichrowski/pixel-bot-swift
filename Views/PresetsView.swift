import SwiftUI

/// View for managing presets
struct PresetsView: View {
    @ObservedObject var bot: TibiaBot
    @State private var selectedPresetId: UUID?
    @State private var newPresetName: String = ""
    @State private var editingName: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("⚙️")
                    .font(.system(size: 14))
                Text("PRESETS")
                    .font(.custom("Press Start 2P", size: 10))
                    .foregroundColor(Theme.gold)
            }
            .padding(.bottom, 4)
            
            // Preset list
            if bot.presets.isEmpty {
            Text("No presets yet")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textDim)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(bot.presets) { preset in
                            PresetRow(
                                preset: preset,
                                isSelected: selectedPresetId == preset.id,
                                isActive: bot.activePresetId == preset.id,
                                onSelect: { selectedPresetId = preset.id }
                            )
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
            
            Divider()
                .background(Theme.borderMid)
                .padding(.vertical, 4)
            
            // Selected preset actions
            if let selectedId = selectedPresetId,
               let preset = bot.presets.first(where: { $0.id == selectedId }) {
                
                // Rename field
                HStack(spacing: 4) {
                    Text("Name:")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textDim)
                    
                    TextField("", text: $editingName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 120)
                        .onAppear { editingName = preset.name }
                        .onChange(of: selectedPresetId) { _ in
                            if let id = selectedPresetId,
                               let p = bot.presets.first(where: { $0.id == id }) {
                                editingName = p.name
                            }
                        }
                    
                    Button("Rename") {
                        bot.renamePreset(id: selectedId, name: editingName)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 9))
                }
                
                HStack(spacing: 6) {
                    Button("📥 Load") {
                        bot.loadPreset(id: selectedId)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 10))
                    
                    Button("💾 Save") {
                        bot.saveToPreset(id: selectedId)
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 10))
                    
                    Button("🗑️ Delete") {
                        bot.deletePreset(id: selectedId)
                        selectedPresetId = bot.presets.first?.id
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.error)
                    .font(.system(size: 10))
                }
            }
            
            Divider()
                .background(Theme.borderMid)
                .padding(.vertical, 4)
            
            // New preset
            HStack(spacing: 4) {
                TextField("New preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 140)
                
                Button("➕ Create") {
                    if !newPresetName.isEmpty {
                        let id = bot.createPreset(name: newPresetName)
                        selectedPresetId = id
                        newPresetName = ""
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 10))
                .disabled(newPresetName.isEmpty)
            }
            
            Spacer()
        }
        .padding(12)
        .onAppear {
            // Select first preset or active preset
            if let activeId = bot.activePresetId {
                selectedPresetId = activeId
            } else {
                selectedPresetId = bot.presets.first?.id
            }
        }
    }
}

/// Row for a single preset
struct PresetRow: View {
    let preset: PresetConfig
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                if isActive {
                    Text("✓")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.success)
                }
                
                Text(preset.name)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Theme.gold : Theme.text)
                
                Spacer()
                
                if preset.regions.isFullyConfigured {
                    Text("📍")
                        .font(.system(size: 10))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Theme.bgLight.opacity(0.8) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
