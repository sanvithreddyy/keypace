import SwiftUI

/// The menu-bar panel's palette: the system's translucent material darkened with a neutral tint, and
/// cards washed lighter on top, so it reads dark over any wallpaper without a color cast.
enum Theme {
    /// Laid over the panel's material.
    static let panelTint = Color.black.opacity(0.32)
    /// Cards and the tab bar.
    static let surface = Color.white.opacity(0.07)
    /// Tiles and chips sitting on a card.
    static let raised = Color.white.opacity(0.06)
}
