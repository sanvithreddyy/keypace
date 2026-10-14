import SwiftUI

/// The menu-bar panel's solid dark palette, so it reads the same over any wallpaper.
enum Theme {
    /// #252D38
    static let panel = Color(red: 0x25 / 255, green: 0x2D / 255, blue: 0x38 / 255)
    /// #393C41
    static let surface = Color(red: 0x39 / 255, green: 0x3C / 255, blue: 0x41 / 255)
    /// A step lighter than `surface`, for tiles and chips sitting on it.
    static let raised = Color.white.opacity(0.06)
}
