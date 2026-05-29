import SwiftUI

// MARK: - Scroll-aware budget title (issue #117)

extension BudgetDetailView {
  /// The icon (decorative leading view) + name as an `HStack`, so the icon mirrors
  /// to the leading edge in RTL — matching `BudgetRowView.nameText` and the Add/Edit
  /// picker chip. The trailing space baked into the icon text reproduces a single
  /// text-space gap, so `spacing` is 0.
  var iconNameStack: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      if let icon = budget.icon, !icon.isEmpty {
        Text(verbatim: "\(icon) ")
      }
      Text(budget.name)
    }
  }

  /// Content-area large title: large-title/bold typography that wraps long names in
  /// full (no truncation). Measures its own height to drive the scroll-collapse
  /// threshold. VoiceOver reads the name only (icon decorative) and treats it as the
  /// screen heading.
  var titleHeader: some View {
    iconNameStack
      .font(.largeTitle)
      .fontWeight(.bold)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(budget.name)
      .accessibilityAddTraits(.isHeader)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { newHeight in
        titleHeight = newHeight
      }
  }

  /// Inline nav-bar title: the same icon-leading content, truncated to one line at
  /// the standard inline-title weight, crossfading in as the large title scrolls
  /// away. Hidden from VoiceOver while invisible so it doesn't double-announce the
  /// name alongside the content header.
  var inlineTitle: some View {
    iconNameStack
      .font(.headline)
      .lineLimit(1)
      .opacity(showInlineTitle ? 1 : 0)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(budget.name)
      .accessibilityHidden(!showInlineTitle)
  }
}
