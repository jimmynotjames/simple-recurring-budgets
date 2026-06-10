import SwiftUI

/// Returns `.secondary` when `dimmed` is true, otherwise the supplied `activeStyle`,
/// erased to `AnyShapeStyle` so the result can be used directly with `.foregroundStyle(...)`.
///
/// Use for the paused-state presentation (F-7.06) where the active foreground is a
/// concrete style (e.g. `Color.moneyDeficit`, `Color.primary`) and the paused
/// substitute is `.secondary`.
func dimmedStyle(_ activeStyle: some ShapeStyle, when dimmed: Bool) -> AnyShapeStyle {
  dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(activeStyle)
}
