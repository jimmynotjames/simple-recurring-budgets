import SwiftUI

extension View {
  /// Applies the standard page background, including the navigation bar. The content
  /// background fills safe areas and shows through the transparent large-title bar;
  /// `toolbarBackground` keeps the color consistent once the compact bar appears on scroll.
  func appBackground() -> some View {
    background(Color("AppBackground").ignoresSafeArea())
      .toolbarBackground(Color("AppBackground"), for: .navigationBar)
  }
}
