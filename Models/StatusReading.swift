import Foundation

/// Current HP and Mana status reading from OCR
struct StatusReading {
    var hpCurrent: Int?
    var hpMax: Int?
    var manaCurrent: Int?
    var manaMax: Int?
    
    /// HP percentage (0-100)
    var hpPercent: Double {
        guard let current = hpCurrent, let max = hpMax, max > 0 else { return 100.0 }
        return (Double(current) / Double(max)) * 100.0
    }
    
    /// Mana percentage (0-100)
    var manaPercent: Double {
        guard let current = manaCurrent, let max = manaMax, max > 0 else { return 100.0 }
        return (Double(current) / Double(max)) * 100.0
    }
    
    /// Formatted HP string
    var hpString: String {
        guard let current = hpCurrent, let max = hpMax else { return "---/---" }
        return "\(current)/\(max)"
    }
    
    /// Formatted Mana string
    var manaString: String {
        guard let current = manaCurrent, let max = manaMax else { return "---/---" }
        return "\(current)/\(max)"
    }
}
