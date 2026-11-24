import SwiftUI

extension ShapeStyle where Self == AnyShapeStyle {
  /// De-emphasized text style that clears the accessibility audit's contrast borderline on
  /// every app background. Use instead of `.secondary` / `.primary.opacity(…)` for small
  /// informational copy: system `secondaryLabel` is ~3.3:1 on cream `AppBackground` and
  /// ~3.0:1 on white cells, under WCAG AA 4.5:1 and in the audit's flaky "nearly passed"
  /// band (3:1–4.5:1). 0.62 primary measures ~5.6–5.95:1 on light, ~7–7.8:1 on dark; 0.55
  /// was only +0.10 over the bar.
  ///
  /// Built on concrete `Color.primary`, NOT hierarchical `.primary`: in vibrant contexts
  /// (Form section footers under Liquid Glass) the hierarchical style resolves to the
  /// vibrant secondary base, so an opacity multiplier double-dims it (1.96:1 measured).
  /// Concrete colors composite flatly.
  static var readableSecondary: AnyShapeStyle {
    AnyShapeStyle(Color.primary.opacity(0.62))
  }
}
