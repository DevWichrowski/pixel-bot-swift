import SwiftUI

/// Live status and vitals.
struct StatusView: View {
    @ObservedObject var bot: TibiaBot

    private let featureColumns = Array(
        repeating: GridItem(.flexible(), spacing: 3),
        count: 4
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                runStatusPanel

                VStack(spacing: 3) {
                    StatusSectionHeader(title: "VITALS", icon: .iconHP)

                    VitalReadoutCard(
                        title: "Health",
                        abbreviation: "HP",
                        icon: .iconHP,
                        color: Theme.hp,
                        readout: bot.hpReadout
                    )

                    VitalReadoutCard(
                        title: "Mana",
                        abbreviation: "MP",
                        icon: .iconMana,
                        color: Theme.mana,
                        readout: bot.manaReadout
                    )
                }

                StatusPanel {
                    HStack {
                        Text("Magic Shield")
                        Spacer()
                        Text("\(bot.shieldReadout.state.rawValue) \(bot.shieldReadout.current.map(String.init) ?? "?")/\(bot.shieldReadout.maximum.map(String.init) ?? "?")")
                    }
                    .font(Theme.utilityFont())
                }

                VStack(spacing: 3) {
                    StatusSectionHeader(title: "ACTIVE SYSTEMS", icon: .iconCombo)

                    LazyVGrid(columns: featureColumns, spacing: 3) {
                        FeatureStateTile(
                            title: "Heal",
                            icon: .iconHealing,
                            tint: Theme.hp,
                            isEnabled: $bot.healEnabled
                        )
                        FeatureStateTile(
                            title: "Critical",
                            icon: .iconHealing,
                            tint: Theme.error,
                            isEnabled: $bot.criticalEnabled
                        )
                        FeatureStateTile(
                            title: "Mana",
                            icon: .iconMana,
                            tint: Theme.mana,
                            isEnabled: $bot.manaEnabled
                        )
                        FeatureStateTile(
                            title: "Magic Shield",
                            icon: .iconMana,
                            tint: Theme.mana,
                            isEnabled: $bot.magicShieldEnabled
                        )
                        FeatureStateTile(
                            title: "Spirit",
                            icon: .iconHealing,
                            tint: Theme.success,
                            isEnabled: $bot.spiritPotionHeal
                        )
                        FeatureStateTile(
                            title: "Eater",
                            icon: .iconEating,
                            tint: Theme.eater,
                            isEnabled: $bot.eaterEnabled
                        )
                        FeatureStateTile(
                            title: "Haste",
                            icon: .iconHaste,
                            tint: Theme.haste,
                            isEnabled: $bot.hasteEnabled
                        )
                        FeatureStateTile(
                            title: "Skinner",
                            icon: .iconSkinning,
                            tint: Theme.skinner,
                            isEnabled: $bot.skinnerEnabled
                        )
                        FeatureStateTile(
                            title: bot.comboIsActive ? "Combo live" : "Combo",
                            icon: .iconCombo,
                            tint: Theme.warning,
                            isEnabled: $bot.comboEnabled
                        )
                    }
                }

                if !bot.errorText.isEmpty {
                    StatusPanel(backgroundColor: Theme.error.opacity(0.08)) {
                        Label(bot.errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.utilityFont())
                            .foregroundStyle(Theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("Error: \(bot.errorText)")
                }
            }
            .padding(6)
        }
        .scrollIndicators(.hidden)
        .background {
            TibiaAssetImage(.stoneBackground, resizingMode: .tile)
        }
    }

    private var runStatusPanel: some View {
        StatusPanel {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    TibiaAssetImage(.iconStatus)
                        .frame(width: 18, height: 18)

                    Text("SYSTEM STATUS")
                        .font(Theme.dataFont(weight: .bold))
                        .foregroundStyle(Theme.textDim)

                    Spacer(minLength: 2)

                    RunStateChip(state: bot.runState)
                }

                Text(bot.statusText)
                    .font(Theme.utilityFont())
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        TibiaAssetImage(.iconPermissions)
                            .frame(width: 16, height: 16)

                        Text("PERMISSIONS")
                            .font(Theme.dataFont(weight: .bold))
                            .foregroundStyle(Theme.textDim)
                    }

                    Spacer(minLength: 2)

                    PermissionChip(
                        title: "Screen Recording",
                        systemImage: "rectangle.inset.filled",
                        isGranted: bot.screenRecordingGranted,
                        help: "Screen Recording permission is required for OCR"
                    )
                    PermissionChip(
                        title: "Accessibility",
                        systemImage: "keyboard",
                        isGranted: bot.accessibilityGranted,
                        help: "Accessibility permission is required for keyboard and mouse input"
                    )
                }
                .padding(.top, 4)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Theme.borderMid)
                        .frame(height: 1)
                }
            }
        }
    }
}

private struct StatusPanel<Content: View>: View {
    let backgroundColor: Color
    let content: Content

    init(
        backgroundColor: Color = Theme.bgPanel,
        @ViewBuilder content: () -> Content
    ) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        content
            .padding(6)
            .background(backgroundColor)
            .overlay {
                Rectangle()
                    .strokeBorder(Theme.borderMid, lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

private struct StatusSectionHeader: View {
    let title: String
    let icon: TibiaAsset

    var body: some View {
        HStack(spacing: 5) {
            TibiaAssetImage(icon)
                .frame(width: 16, height: 16)

            Text(title)
                .font(Theme.dataFont(weight: .bold))
                .foregroundStyle(Theme.textBright)

            Rectangle()
                .fill(Theme.borderMid)
                .frame(height: 1)
        }
        .frame(height: 20)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct RunStateChip: View {
    let state: BotRunState

    var body: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(state.tacticalColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(state.tacticalTitle.uppercased())
                .font(Theme.dataFont(weight: .semibold))
                .foregroundStyle(state.tacticalColor)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bot state")
        .accessibilityValue(state.tacticalTitle)
        .help(state.tacticalHelp)
    }
}

private struct PermissionChip: View {
    let title: String
    let systemImage: String
    let isGranted: Bool
    let help: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(isGranted ? Theme.Icons.check : Theme.Icons.cross)
                .font(Theme.dataFont(weight: .bold))
        }
        .foregroundStyle(isGranted ? Theme.success : Theme.error)
        .padding(.horizontal, 4)
        .frame(height: 20)
        .background(Theme.bgDark.opacity(0.55))
        .overlay {
            Rectangle()
                .strokeBorder(isGranted ? Theme.success.opacity(0.55) : Theme.error.opacity(0.55), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) permission")
        .accessibilityValue(isGranted ? "Granted" : "Missing")
        .help(help)
    }
}

private struct VitalReadoutCard: View {
    let title: String
    let abbreviation: String
    let icon: TibiaAsset
    let color: Color
    let readout: NumericReadout

    private var fraction: Double {
        guard let current = readout.current,
              let maximum = readout.maximum,
              maximum > 0 else {
            return 0
        }
        return min(max(Double(current) / Double(maximum), 0), 1)
    }

    private var readoutText: String {
        let current = readout.current.map(String.init) ?? "---"
        let maximum = readout.maximum.map(String.init) ?? "---"
        return "\(current)/\(maximum)"
    }

    private var percentageText: String {
        guard readout.current != nil, readout.maximum != nil else { return "--%" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    var body: some View {
        StatusPanel {
            HStack(spacing: 6) {
                TibiaAssetImage(icon)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(title)
                            .font(Theme.dataFont(weight: .bold))
                            .foregroundStyle(Theme.textBright)

                        Text(abbreviation)
                            .font(Theme.dataFont())
                            .foregroundStyle(Theme.textDim)

                        Spacer(minLength: 4)

                        Text(readoutText)
                            .font(Theme.dataFont(weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textBright)

                        Text(percentageText)
                            .font(Theme.dataFont(weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(color)

                        if readout.state != .valid {
                            Text(readout.state.tacticalTitle.uppercased())
                                .font(Theme.dataFont(weight: .bold))
                                .foregroundStyle(readout.state.tacticalColor)
                                .lineLimit(1)
                        }
                    }

                    FlatProgressBar(
                        fraction: fraction,
                        color: color
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(readoutText), \(percentageText), \(readout.state.tacticalTitle)")
        .help(readout.state == .stale ? "The last value is visible but cannot trigger actions" : "Latest accepted OCR value")
    }
}

private struct FlatProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Theme.bgDark

                Rectangle()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * fraction - 2))
                    .padding(1)
            }
            .overlay {
                Rectangle().strokeBorder(Theme.borderShadow, lineWidth: 1)
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }
}

private struct FeatureStateTile: View {
    let title: String
    let icon: TibiaAsset
    let tint: Color
    @Binding var isEnabled: Bool

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    TibiaAssetImage(icon)
                        .frame(width: 17, height: 17)
                        .opacity(isEnabled ? 1 : 0.35)

                    Spacer(minLength: 0)

                    Rectangle()
                        .fill(isEnabled ? tint : Theme.borderMid)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(Theme.utilityFont(weight: .medium))
                    .foregroundStyle(isEnabled ? Theme.textBright : Theme.textDim)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Theme.bgPanel)
            .overlay {
                Rectangle()
                    .strokeBorder(Theme.borderMid, lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tacticalFocusRing(cornerRadius: 0)
        .accessibilityLabel(title)
        .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
        .help("\(isEnabled ? "Disable" : "Enable") \(title)")
    }
}

extension BotRunState {
    var tacticalTitle: String {
        switch self {
        case .stopped: "Stopped"
        case .needsPermission: "Needs permission"
        case .starting: "Starting"
        case .running: "Running"
        case .captureFailed: "Capture failed"
        case .stale: "Data stale"
        }
    }

    var tacticalColor: Color {
        switch self {
        case .stopped: Theme.textDim
        case .needsPermission, .captureFailed: Theme.error
        case .starting: Theme.gold
        case .running: Theme.success
        case .stale: Theme.warning
        }
    }

    var tacticalHelp: String {
        switch self {
        case .stopped: "Capture and input are stopped"
        case .needsPermission: "Grant Screen Recording and Accessibility permissions"
        case .starting: "Waiting for the first complete capture frame"
        case .running: "Capture is active and OCR data is fresh"
        case .captureFailed: "The capture stream failed"
        case .stale: "Required OCR data has not been confirmed for more than 250 milliseconds"
        }
    }
}

private extension NumericReadoutState {
    var tacticalTitle: String {
        switch self {
        case .valid: "Fresh"
        case .stale: "Stale"
        case .invalid: "Invalid"
        case .unconfigured: "Unconfigured"
        }
    }

    var tacticalColor: Color {
        switch self {
        case .valid: Theme.success
        case .stale: Theme.warning
        case .invalid: Theme.error
        case .unconfigured: Theme.textDim
        }
    }
}
