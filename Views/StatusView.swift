import SwiftUI

/// Status tab showing vitals and controls
struct StatusView: View {
    @ObservedObject var bot: TibiaBot
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Status Panel
                PixelArtPanel {
                    HStack {
                        Circle()
                            .fill(bot.isRunning ? Theme.success : Theme.textDim)
                            .frame(width: 8, height: 8)
                        
                        Text(bot.statusText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.text)
                        
                        Spacer()
                    }
                }
                
                // Vitals Section
                SectionHeader(title: "VITALS", icon: Theme.Icons.hp)
                
                PixelArtPanel {
                    VStack(spacing: 4) {
                        // HP
                        HStack {
                            Text("\(Theme.Icons.hp) HP:")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.hp)
                            
                            Spacer()
                            
                            Text(bot.hpString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textBright)
                        }
                        
                        // Mana
                        HStack {
                            Text("\(Theme.Icons.mana) MP:")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.mana)
                            
                            Spacer()
                            
                            Text(bot.manaString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textBright)
                        }
                    }
                }
                
                // Controls Section
                SectionHeader(title: "CONTROLS", icon: "⚔")
                
                PixelArtPanel {
                    VStack(spacing: 4) {
                        ThresholdRow(
                            label: "Heal",
                            icon: Theme.Icons.heal,
                            color: Theme.hp,
                            isOn: $bot.healEnabled,
                            threshold: $bot.healThreshold
                        )
                        
                        ThresholdRow(
                            label: "Crit",
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
                    }
                }
                
                // Extras Section
                SectionHeader(title: "EXTRAS", icon: "★")
                
                PixelArtPanel {
                    VStack(spacing: 4) {
                        ToggleRow(
                            label: "Eater",
                            icon: Theme.Icons.eater,
                            color: Theme.eater,
                            isOn: $bot.eaterEnabled,
                            hotkey: bot.eaterHotkey
                        )
                        
                        ToggleRow(
                            label: "Haste",
                            icon: Theme.Icons.haste,
                            color: Theme.haste,
                            isOn: $bot.hasteEnabled,
                            hotkey: bot.hasteHotkey
                        )
                        
                        ToggleRow(
                            label: "Skin",
                            icon: Theme.Icons.skinner,
                            color: Theme.skinner,
                            isOn: $bot.skinnerEnabled,
                            hotkey: bot.skinnerHotkey
                        )
                        
                        ToggleRow(
                            label: "Combo",
                            icon: "⚔",
                            color: Theme.warning,
                            isOn: $bot.comboEnabled,
                            hotkey: bot.comboHotkey
                        )
                    }
                }
                
                // Start/Stop Button
                HStack {
                    Spacer()
                    
                    PixelButton(
                        bot.isRunning ? "\(Theme.Icons.stop) STOP" : "\(Theme.Icons.start) START",
                        color: bot.isRunning ? Theme.error : Theme.success
                    ) {
                        bot.toggle()
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
                
                // Error message
                if !bot.errorText.isEmpty {
                    Text(bot.errorText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.error)
                        .padding(.top, 4)
                }
            }
            .padding(4)
        }
    }
}
