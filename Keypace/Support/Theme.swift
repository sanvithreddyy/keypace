import AppKit
import SwiftUI

/// The menu-bar panel's palette: the system's translucent material tinted toward the appearance, and
/// cards washed slightly toward the opposite ink on top, so it reads cleanly over any wallpaper without a color cast.
enum Theme {
    /// Laid over the panel's material.
    static let panelTint = adaptive(dark: .black.withAlphaComponent(0.32), light: .white.withAlphaComponent(0.45))
    /// Cards and the tab bar.
    static let surface = adaptive(dark: .white.withAlphaComponent(0.07), light: .black.withAlphaComponent(0.04))
    /// Tiles and chips sitting on a card.
    static let raised = adaptive(dark: .white.withAlphaComponent(0.06), light: .black.withAlphaComponent(0.04))
    /// The edge of a card.
    static let hairline = adaptive(dark: .white.withAlphaComponent(0.05), light: .black.withAlphaComponent(0.06))
    /// Bordered buttons at rest and pressed, and their edge.
    static let control = adaptive(dark: .white.withAlphaComponent(0.05), light: .black.withAlphaComponent(0.04))
    static let controlPressed = adaptive(dark: .white.withAlphaComponent(0.12), light: .black.withAlphaComponent(0.09))
    static let controlBorder = adaptive(dark: .white.withAlphaComponent(0.1), light: .black.withAlphaComponent(0.1))
    /// Grouped rows in settings.
    static let group = adaptive(dark: .white.withAlphaComponent(0.05), light: .black.withAlphaComponent(0.035))

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}
