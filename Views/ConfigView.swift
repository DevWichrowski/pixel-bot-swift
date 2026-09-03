import SwiftUI

/// Configuration grouped into focused, collapsible sections.
struct ConfigView: View {
    @ObservedObject var bot: TibiaBot

    @State private var regionsExpanded = true
    @State private var healingExpanded = false
    @State private var cooldownsExpanded = false
    @State private var hotkeysExpanded = false
    @State private var comboExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                CollapsibleSection(
                    title: "Regions",
                    icon: "◎",
                    tint: Theme.accent,
                    isExpanded: $regionsExpanded
                ) {
                    VStack(spacing: 6) {
                        RegionDiagnosticCard(
                            title: "Health",
                            icon: Theme.Icons.hp,
                            tint: Theme.hp,
                            regionStatus: bot.hpRegionStatus,
                            diagnostic: bot.hpDiagnostic,
                            screenRecordingGranted: bot.screenRecordingGranted,
                            selectAction: bot.selectHPRegion,
                            refreshAction: { bot.refreshDiagnostic(kind: .hp) }
                        )

                        RegionDiagnosticCard(
                            title: "Mana",
                            icon: Theme.Icons.mana,
                            tint: Theme.mana,
                            regionStatus: bot.manaRegionStatus,
                            diagnostic: bot.manaDiagnostic,
                            screenRecordingGranted: bot.screenRecordingGranted,
                            selectAction: bot.selectManaRegion,
                            refreshAction: { bot.refreshDiagnostic(kind: .mana) }
                        )

                        RegionDiagnosticCard(
                            title: "Ammo",
                            icon: "🏹",
                            tint: Theme.success,
                            regionStatus: bot.ammoRegionStatus,
                            diagnostic: bot.ammoDiagnostic,
                            screenRecordingGranted: bot.screenRecordingGranted,
                            selectAction: bot.selectAmmoRegion,
                            refreshAction: { bot.refreshDiagnostic(kind: .ammo) }
                        )
                    }
                }

                CollapsibleSection(
                    title: "Healing",
                    icon: Theme.Icons.heal,
                    tint: Theme.hp,
                    isExpanded: $healingExpanded
                ) {
                    VStack(spacing: 4) {
                        ThresholdRow(
                            label: "Heal",
                            icon: Theme.Icons.heal,
                            color: Theme.hp,
                            isOn: $bot.healEnabled,
                            threshold: $bot.healThreshold
                        )
                        ThresholdRow(
                            label: "Critical",
                            icon: Theme.Icons.critical,
                            color: Theme.error,
                            isOn: $bot.criticalEnabled,
                            threshold: $bot.criticalThreshold
                        )
                        ThresholdRow(
                            label: "Mana",
                            icon: Theme.Icons.mana,
                            color: Theme.mana,
                            isOn: $bot.manaEnabled,
                            threshold: $bot.manaThreshold
                        )
                        ThresholdRow(
                            label: "Spirit",
                            icon: "🧪",
                            color: Theme.success,
                            isOn: $bot.spiritPotionHeal,
                            threshold: $bot.spiritPotionThreshold
                        )

                        Divider()
                            .overlay(Theme.borderMid)
                            .padding(.vertical, 4)

                        ToggleRow(
                            label: "Critical uses potion",
                            icon: Theme.Icons.critical,
                            color: Theme.error,
                            isOn: $bot.criticalIsPotion
                        )

                        Text("Potion priority: Critical, then Mana")
                            .font(Theme.utilityFont())
                            .foregroundStyle(Theme.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 22)
                    }
                }

                CollapsibleSection(
                    title: "Cooldowns",
                    icon: "⏱",
                    tint: Theme.gold,
                    isExpanded: $cooldownsExpanded
                ) {
                    VStack(spacing: 4) {
                        HStack {
                            Text("Healing group cooldown:")
                                .font(Theme.utilityFont())
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(bot.healingGroupCooldownText) s")
                                .font(Theme.dataFont())
                                .foregroundStyle(Theme.textDim)
                        }
                        .frame(minHeight: 28)
                        LabeledTextFieldRow(
                            label: "Potion cooldown",
                            text: $bot.potionCooldown,
                            suffix: "s"
                        )
                    }
                }

                CollapsibleSection(
                    title: "Hotkeys",
                    icon: "♪",
                    tint: Theme.accent,
                    isExpanded: $hotkeysExpanded
                ) {
                    VStack(spacing: 4) {
                        HotkeyRow(label: "\(Theme.Icons.heal) Heal", hotkey: $bot.healHotkey)
                        HotkeyRow(label: "\(Theme.Icons.critical) Critical", hotkey: $bot.criticalHotkey)
                        HotkeyRow(label: "\(Theme.Icons.mana) Mana", hotkey: $bot.manaHotkey)
                        HotkeyRow(label: "🧪 Spirit potion", hotkey: $bot.spiritPotionHotkey)
                        HotkeyRow(label: "\(Theme.Icons.eater) Eater", hotkey: $bot.eaterHotkey)
                        HotkeyRow(label: "\(Theme.Icons.haste) Haste", hotkey: $bot.hasteHotkey)
                        HotkeyRow(label: "\(Theme.Icons.skinner) Skinner", hotkey: $bot.skinnerHotkey)

                        Divider()
                            .overlay(Theme.borderMid)
                            .padding(.vertical, 4)

                        ToggleRow(
                            label: "Eater",
                            icon: Theme.Icons.eater,
                            color: Theme.eater,
                            isOn: $bot.eaterEnabled
                        )
                        foodPicker
                        ToggleRow(
                            label: "Haste",
                            icon: Theme.Icons.haste,
                            color: Theme.haste,
                            isOn: $bot.hasteEnabled
                        )
                        ToggleRow(
                            label: "Skinner",
                            icon: Theme.Icons.skinner,
                            color: Theme.skinner,
                            isOn: $bot.skinnerEnabled
                        )
                    }
                }

                CollapsibleSection(
                    title: "Combo",
                    icon: "⚔",
                    tint: Theme.warning,
                    isExpanded: $comboExpanded
                ) {
                    VStack(spacing: 4) {
                        ToggleRow(
                            label: "Auto Combo",
                            icon: "⚔",
                            color: Theme.warning,
                            isOn: $bot.comboEnabled
                        )
                        HotkeyRow(label: "⚔ Start / stop", hotkey: $bot.comboStartStopHotkey)
                        HotkeyRow(label: "⚔ Combo key", hotkey: $bot.comboHotkey)

                        Divider()
                            .overlay(Theme.borderMid)
                            .padding(.vertical, 4)

                        ToggleRow(
                            label: "Utito Tempo",
                            icon: "⚡",
                            color: Theme.accent,
                            isOn: $bot.utitoTempoEnabled
                        )
                        HotkeyRow(label: "⚡ Utito Tempo", hotkey: $bot.utitoTempoHotkey)
                        ToggleRow(
                            label: "Re-cast Utito",
                            icon: "🔄",
                            color: Theme.warning,
                            isOn: $bot.recastUtito
                        )

                        Divider()
                            .overlay(Theme.borderMid)
                            .padding(.vertical, 4)

                        ToggleRow(
                            label: "Paladin Combo",
                            icon: "🏹",
                            color: Theme.success,
                            isOn: $bot.paladinComboEnabled
                        )
                        Text("Triggers once when the accepted ammo value decreases")
                            .font(Theme.utilityFont())
                            .foregroundStyle(Theme.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 22)

                        Divider()
                            .overlay(Theme.borderMid)
                            .padding(.vertical, 4)

                        ToggleRow(
                            label: "Loot on stop",
                            icon: "📦",
                            color: Theme.success,
                            isOn: $bot.lootOnStop
                        )
                        HotkeyRow(label: "📦 Loot key", hotkey: $bot.autoLootHotkey)
                    }
                }

                PixelButton("🔄  RESET CONFIG", color: Theme.warning, fillWidth: true) {
                    bot.resetConfig()
                }
                .help("Restore default settings and clear all capture regions")
                .padding(.top, 2)
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .background {
            TibiaAssetImage(.stoneBackground, resizingMode: .tile)
        }
    }

    private var foodPicker: some View {
        HStack(spacing: 6) {
            Text("Food type")
                .font(Theme.utilityFont())
                .foregroundStyle(Theme.text)

            Spacer()

            Picker("Food type", selection: $bot.foodType) {
                Text("Fire Mushroom").tag("fire_mushroom")
                Text("Brown Mushroom").tag("brown_mushroom")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 154)
            .padding(.horizontal, 4)
            .frame(minHeight: 28)
            .background(Theme.bgDark)
            .tibiaFrame(.fieldFrame, insets: EdgeInsets(top: 11, leading: 11, bottom: 11, trailing: 11))
            .accessibilityLabel("Food type")
            .help("Choose the food used by Auto Eater")
        }
        .frame(minHeight: 26)
    }
}

private struct RegionDiagnosticCard: View {
    let title: String
    let icon: String
    let tint: Color
    let regionStatus: String
    let diagnostic: RegionDiagnostic?
    let screenRecordingGranted: Bool
    let selectAction: () -> Void
    let refreshAction: () -> Void

    private var isConfigured: Bool {
        if let diagnostic {
            switch diagnostic.state {
            case .unconfigured:
                break
            case .valid, .stale, .invalid:
                return true
            }
        }

        return regionStatus.hasPrefix(Theme.Icons.check)
    }

    private var diagnosticStateTitle: String {
        guard let diagnostic else { return "Unconfigured" }
        switch diagnostic.state {
        case .valid: return "Fresh"
        case .stale: return "Stale"
        case .invalid: return "Invalid"
        case .unconfigured: return "Unconfigured"
        }
    }

    private var diagnosticStateColor: Color {
        guard let diagnostic else { return Theme.textDim }
        switch diagnostic.state {
        case .valid: return Theme.success
        case .stale: return Theme.warning
        case .invalid: return Theme.error
        case .unconfigured: return Theme.textDim
        }
    }

    private var refreshHelp: String {
        if !screenRecordingGranted {
            return "Screen Recording permission is required before this test can run"
        }
        if !isConfigured {
            return "Select the region before running an OCR test"
        }
        return "Read this region from the current stream frame, or perform a one-frame capture while stopped"
    }

    var body: some View {
        TacticalInsetPanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    TibiaSymbol(symbol: icon, tint: tint)
                    Text("\(title) region")
                        .font(Theme.headingFont())
                        .foregroundStyle(Theme.textBright)

                    Spacer()

                    Text(diagnosticStateTitle.uppercased())
                        .font(Theme.dataFont(weight: .bold))
                        .foregroundStyle(diagnosticStateColor)
                        .padding(.horizontal, 4)
                        .frame(height: 20)
                        .background(diagnosticStateColor.opacity(0.1))
                        .overlay {
                            Rectangle()
                                .strokeBorder(diagnosticStateColor.opacity(0.55), lineWidth: 1)
                        }
                }

                Text(isConfigured ? regionStatus : "Unconfigured")
                    .font(Theme.dataFont())
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !screenRecordingGranted {
                    Label(
                        "Screen Recording permission is required to refresh this test.",
                        systemImage: "lock.trianglebadge.exclamationmark"
                    )
                    .font(Theme.utilityFont())
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
                } else if !isConfigured {
                    Text("Select a region to create an OCR diagnostic.")
                        .font(Theme.utilityFont())
                        .foregroundStyle(Theme.textDim)
                }

                HStack(spacing: 5) {
                    DiagnosticThumbnail(
                        title: "Raw",
                        image: diagnostic?.rawImage,
                        background: Theme.bgPanel
                    )
                    DiagnosticThumbnail(
                        title: "Binary",
                        image: diagnostic?.binaryImage,
                        background: Color.white
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    DiagnosticValueRow(
                        label: "OCR",
                        value: diagnosticText,
                        valueColor: Theme.textBright
                    )
                    HStack(spacing: 6) {
                        DiagnosticMetric(label: "Confidence", value: confidenceText)
                        DiagnosticMetric(label: "Freshness", value: freshnessText)
                        DiagnosticMetric(label: "Latency", value: latencyText)
                    }
                }

                HStack(spacing: 5) {
                    PixelButton("Select region", color: tint, fillWidth: true, compact: true, action: selectAction)
                        .help("Select the \(title.lowercased()) readout on the main display")

                    PixelButton("Refresh test", color: Theme.accent, fillWidth: true, compact: true, action: refreshAction)
                        .disabled(!screenRecordingGranted || !isConfigured)
                        .help(refreshHelp)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) region diagnostic")
    }

    private var diagnosticText: String {
        guard let text = diagnostic?.text, !text.isEmpty else { return "No OCR text" }
        return text
    }

    private var confidenceText: String {
        guard let diagnostic else { return "--" }
        return String(format: "%.0f%%", Double(diagnostic.confidence) * 100)
    }

    private var freshnessText: String {
        guard let freshness = diagnostic?.freshness else { return "Never" }
        if freshness < 1 {
            return String(format: "%.0f ms", freshness * 1_000)
        }
        return String(format: "%.1f s", freshness)
    }

    private var latencyText: String {
        guard let diagnostic else { return "--" }
        return String(format: "%.1f ms", diagnostic.latency * 1_000)
    }
}

private struct DiagnosticThumbnail: View {
    let title: String
    let image: CGImage?
    let background: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.utilityFont(weight: .medium))
                .foregroundStyle(Theme.textDim)

            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.textDim.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .background(background)
            .tibiaFrame(.fieldFrame, insets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) region preview")
        .accessibilityValue(image == nil ? "Unavailable" : "Available")
    }
}

private struct DiagnosticValueRow: View {
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(label)
                .font(Theme.utilityFont())
                .foregroundStyle(Theme.textDim)
            Text(value)
                .font(Theme.dataFont(weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct DiagnosticMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Theme.utilityFont())
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(Theme.dataFont(weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
