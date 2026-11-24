import SwiftUI

// MARK: - Scroll-aware budget title

extension BudgetDetailView {
  /// Icon (decorative) + name as one `Text` paragraph. Wrapped lines flow to the leading
  /// margin (the icon only offsets the first line), and the icon mirrors in RTL via the
  /// bidi base direction (the neutral emoji takes the name's writing direction). Don't
  /// switch to a leading `HStack` icon as on the list row: it reserves a column and
  /// indents every wrapped line. The space in the string is the icon-name gap.
  private var titleText: Text {
    guard let icon = budget.icon, !icon.isEmpty else { return Text(budget.name) }
    return Text(verbatim: "\(icon) \(budget.name)")
  }

  /// Content-area large title; wraps long names in full and measures its own height for
  /// the scroll-collapse threshold. VoiceOver reads the name only, as the screen heading.
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

  /// Inline nav-bar title: same icon + name, one line, crossfading in as the large title
  /// scrolls away. Hidden from VoiceOver while invisible to avoid double-announcing.
  var inlineTitle: some View {
    titleText
      .font(.headline)
      .lineLimit(1)
      .opacity(showInlineTitle ? 1 : 0)
      .accessibilityLabel(budget.name)
      .accessibilityHidden(!showInlineTitle)
  }
}
