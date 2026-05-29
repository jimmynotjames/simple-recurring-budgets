import SwiftUI

// MARK: - Scroll-aware budget title (issue #117)

extension BudgetDetailView {
  /// The icon (decorative) + name as a single concatenated `Text`, so the title lays
  /// out as one paragraph: wrapped lines flow to the leading margin (the icon only
  /// offsets the first line, not subsequent ones), and the icon still mirrors to the
  /// leading edge in RTL via the bidi base direction (the leading neutral emoji
  /// attaches to the name's writing direction). A leading `HStack` icon — as on the
  /// list row — would instead reserve a left column and indent every wrapped line
  /// past it. The trailing space baked into the icon text reproduces a single
  /// text-space gap.
  private var titleText: Text {
    guard let icon = budget.icon, !icon.isEmpty else { return Text(budget.name) }
    return Text(verbatim: "\(icon) \(budget.name)")
  }

  /// Content-area large title: large-title/bold typography that wraps long names in
  /// full (no truncation). Measures its own height to drive the scroll-collapse
  /// threshold. VoiceOver reads the name only (icon decorative) and treats it as the
  /// screen heading.
  var titleHeader: some View {
    titleText
      .font(.largeTitle)
      .fontWeight(.bold)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel(budget.name)
      .accessibilityAddTraits(.isHeader)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { newHeight in
        titleHeight = newHeight
      }
  }

  /// Inline nav-bar title: the same icon + name, truncated to one line at the
  /// standard inline-title weight, crossfading in as the large title scrolls away.
  /// Hidden from VoiceOver while invisible so it doesn't double-announce the name
  /// alongside the content header.
  var inlineTitle: some View {
    titleText
      .font(.headline)
      .lineLimit(1)
      .opacity(showInlineTitle ? 1 : 0)
      .accessibilityLabel(budget.name)
      .accessibilityHidden(!showInlineTitle)
  }
}
