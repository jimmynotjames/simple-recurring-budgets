## 1. Content-area large title

- [x] 1.1 In `BudgetDetailView`, remove `.navigationTitle(budget.iconPrefixedName)` and add `.navigationBarTitleDisplayMode(.inline)`.
- [x] 1.2 Add a leading-aligned title header view: `HStack(alignment: .firstTextBaseline, spacing: 0)` with `Text(verbatim: "\(icon) ")` (when icon set) + `Text(budget.name)`, styled `.font(.largeTitle).fontWeight(.bold)`, `.multilineTextAlignment(.leading)`, wrapping (no `lineLimit`), `.frame(maxWidth: .infinity, alignment: .leading)` — mirroring `BudgetRowView.nameText`.
- [x] 1.3 Render the title header as a new first `List` section with `.listRowBackground(Color.clear)`, `.listRowSeparator(.hidden)`, and `.listRowInsets` tuned to match the system large-title leading margin.

## 2. Scroll-aware collapse

- [x] 2.1 Measure the header height with `.onGeometryChange(for: CGFloat.self) { $0.size.height }` into local `@State`.
- [x] 2.2 Add `@State private var showInlineTitle = false`; apply `.onScrollGeometryChange(for: Bool.self)` to the `List` computing `geo.contentOffset.y + geo.contentInsets.top > collapseThreshold` (~0.6 × measured header height) and update `showInlineTitle` inside `withAnimation(.easeInOut)`.
- [x] 2.3 Add a `ToolbarItem(placement: .principal)` rendering the same icon-leading `HStack` + name, `.lineLimit(1)`, `.font(.headline)`, `.opacity(showInlineTitle ? 1 : 0)` so it crossfades in/out as the content title scrolls.

## 3. Accessibility (cross-cutting §6.8)

- [x] 3.1 On the content title header: `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(budget.name)` + `.accessibilityAddTraits(.isHeader)` so VoiceOver reads the name only (icon decorative) and treats it as the screen heading.
- [x] 3.2 Verify Dynamic Type: the large title scales and wraps without clipping; the inline title truncates cleanly at large sizes. (Uses scaling `.largeTitle`/`.headline` text styles and no fixed-height frames; covered by previews.)

## 4. Cleanup & remaining cross-cutting

- [x] 4.1 Check callers of `Budget.iconPrefixedName`; remove it (and any now-dead helper) if the detail title was its only production caller, or retain with a note if tests/other surfaces use it. (Removed — its only caller was the detail nav title; no test references.)
- [x] 4.2 Localized source strings: confirm no new user-facing strings are introduced (title renders existing `name`/`icon`) — N/A, no new keys.
- [x] 4.3 Translations: N/A — no string-catalog keys added or changed, so the `translate-new-strings` pipeline is a no-op.
- [x] 4.4 Mixpanel analytics: N/A — no new user-initiated state-changing action (cosmetic title rendering only), so no new event.

## 5. Previews & docs

- [x] 5.1 Verify/extend `BudgetDetailView` previews to cover: long wrapping name, with/without icon, RTL (`environment(\.layoutDirection, .rightToLeft)`), and Dark Mode.
- [x] 5.2 Update `docs/product-features-planning.md` F-4.03 acceptance wording: the detail title renders the icon as a leading **view** (RTL-correct), not a string prefix.

## 6. Build & verify

- [x] 6.1 Run the four-step gate: `make format` → `make lint-fix` → `make build` → `make test`; fix any failures.
- [x] 6.2 Run `/opsx:verify` and resolve everything it flags.
