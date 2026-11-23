import SwiftUI

/// `.secondary` when `dimmed`, otherwise `activeStyle`, erased to `AnyShapeStyle` for
/// `.foregroundStyle(...)`. For paused-state presentation, where the active foreground is a
/// concrete style (e.g. `Color.moneyDeficit`) and the paused substitute is `.secondary`.
func dimmedStyle(_ activeStyle: some ShapeStyle, when dimmed: Bool) -> AnyShapeStyle {
  dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(activeStyle)
}
