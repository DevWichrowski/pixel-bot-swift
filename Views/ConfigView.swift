import SwiftUI

/// Config tab for regions and hotkeys
struct ConfigView: View {
    @ObservedObject var bot: TibiaBot
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Regions Section
                SectionHeader(title: "REGIONS", icon: "◎")
                
                PixelArtPanel {
                    VStack(spacing: 8) {
                        // HP Region
                        HStack {
                            Text("\(Theme.Icons.hp) HP Region")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.hp)
                            
                            Spacer()
                            
                            PixelButton("SELECT", color: Theme.accent) {
                                bot.selectHPRegion()
                            }
                        }
                        
                        Text(bot.hpRegionStatus)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Mana Region
                        HStack {
                            Text("\(Theme.Icons.mana) Mana Region")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.mana)
                            
                            Spacer()
                            
                            PixelButton("SELECT", color: Theme.accent) {
                                bot.selectManaRegion()
                            }
                        }
                        
                        Text(bot.manaRegionStatus)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                // Food Section
                SectionHeader(title: "FOOD", icon: Theme.Icons.eater)
                
                PixelArtPanel {
                    VStack(spacing: 4) {
                        HStack {
                            Text("Type:")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.text)
                            
                            Spacer()
                            
                            Picker("", selection: $bot.foodType) {
                                Text("Fire Mushroom").tag("fire_mushroom")
                                Text("Brown Mushroom").tag("brown_mushroom")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                        }
                        
                        HStack {
                            Text("Key:")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.text)
                            
                            Spacer()
                            
                            TextField("", text: $bot.eaterHotkey)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(width: 50, height: 20)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                
                // Potion Mode Section
                SectionHeader(title: "POTION MODE", icon: Theme.Icons.critical)
                
                PixelArtPanel {
                    VStack(spacing: 4) {
                        ToggleRow(
                            label: "Crit is Potion",
                            icon: Theme.Icons.critical,
                            color: Theme.error,
                            isOn: $bot.criticalIsPotion
                        )
                        
                        Text("Priority: Crit > Mana")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Theme.textDim)
                            .padding(.leading, 16)
                    }
                }
                
                // Hotkeys Section
                SectionHeader(title: "HOTKEYS", icon: "♪")
                
                PixelArtPanel {
                    VStack(spacing: 4) {
                        HotkeyRow(label: "\(Theme.Icons.heal) Heal:", hotkey: $bot.healHotkey)
                        HotkeyRow(label: "\(Theme.Icons.critical) Crit:", hotkey: $bot.criticalHotkey)
                        HotkeyRow(label: "\(Theme.Icons.mana) Mana:", hotkey: $bot.manaHotkey)
                        HotkeyRow(label: "\(Theme.Icons.haste) Haste:", hotkey: $bot.hasteHotkey)
                        HotkeyRow(label: "\(Theme.Icons.skinner) Skin:", hotkey: $bot.skinnerHotkey)
                    }
                }
                
                // Auto Combo Section
                SectionHeader(title: "AUTO COMBO", icon: "⚔")
                
                PixelArtPanel {
                    VStack(spacing: 4) {
                        HotkeyRow(label: "⚔ Start/Stop:", hotkey: $bot.comboStartStopHotkey)
                        HotkeyRow(label: "⚔ Combo Key:", hotkey: $bot.comboHotkey)
                        
                        Divider().background(Theme.textDim)
                        
                        ToggleRow(
                            label: "Loot on Stop",
                            icon: "📦",
                            color: Theme.success,
                            isOn: $bot.lootOnStop
                        )
                        
                        HotkeyRow(label: "📦 Loot Key:", hotkey: $bot.autoLootHotkey)
                    }
                }
                
                // Reset Button
                HStack {
                    Spacer()
                    
                    PixelButton("🔄 RESET CONFIG", color: Theme.warning) {
                        bot.resetConfig()
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(4)
        }
    }
}
