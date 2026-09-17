import SwiftUI

// Backs the hex literals in the generated Tokens.swift (design/generate-tokens.mjs).
// Tokens are RGB only per design/tokens.json — no alpha channel in the source file.
extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
