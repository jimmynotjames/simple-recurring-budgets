import SwiftUI

extension ShapeStyle where Self == AnyShapeStyle {
  /// De-emphasized text style that stays clear of the accessibility audit's
  /// contrast borderline on every background the app uses (issue #223).
  ///
  /// Use this instead of `.secondary` / `.primary.opacity(…)` for small
  /// (sub-large-text) informational copy. The system `secondaryLabel` composites
  /// to ~3.3:1 against the light cream `AppBackground` and ~3.0:1 against white
  /// cells — below the WCAG AA 4.5:1 bar for small text and inside the audit's
  /// "Contrast nearly passed" band (3:1–4.5:1), which flakes under parallel-clone
  /// rendering variance. The previous 0.55 calibration measured 4.60:1 on cream —
  /// above the bar but with only +0.10 margin.
  ///
  /// 0.62 primary measures 5.95:1 on light cream, ~5.6:1 on white cells, and
  /// 7.8:1 / ~7:1 on the dark variants — comfortably past the borderline in both
  /// color schemes.
  ///
  /// Built on concrete `Color.primary`, NOT hierarchical `.primary`: in vibrant
  /// contexts (Form section footers under Liquid Glass) the hierarchical style
  /// resolves to the context's vibrant secondary base, so an opacity multiplier
  /// double-dims it (measured 1.96:1 in the #223 investigation). Concrete colors
  /// composite flatly.
  static var readableSecondary: AnyShapeStyle {
    AnyShapeStyle(Color.primary.opacity(0.62))
  }
}
