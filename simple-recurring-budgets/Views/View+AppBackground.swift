//
//  View+AppBackground.swift
//  simple-recurring-budgets
//

import SwiftUI

extension View {
    /// Applies the app's standard page background to a screen, including the navigation bar.
    ///
    /// The content background fills the full screen (including safe areas) and shows through
    /// the transparent nav bar when the large title is visible. `toolbarBackground` kicks in
    /// when the user scrolls and the compact bar appears, keeping the colour consistent.
    func appBackground() -> some View {
        self
            .background(Color("AppBackground").ignoresSafeArea())
            .toolbarBackground(Color("AppBackground"), for: .navigationBar)
    }
}
