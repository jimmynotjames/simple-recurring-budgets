## Context

`BudgetDetailView` is a `List`-based screen (status header, primary action, expense sections) that sets its title with `.navigationTitle(budget.iconPrefixedName)` — a `String` of the form `"☕ Coffee"`. A string title can't (a) place a bidi-neutral emoji on the leading edge in RTL (it pins left in Arabic), (b) wrap a long name, or (c) keep the large-title look under our control. The Budgets list row already solved the RTL problem by rendering the icon as a leading `HStack` view (`BudgetRowView.nameText`); this change brings the detail title to the same model and adds the large→inline scroll collapse described in issue #117.

Deployment target is iOS 26.5, so `onScrollGeometryChange(for:of:action:)`, `onGeometryChange(for:of:)`, and custom `.principal` toolbar items are all available. The screen is a plain View (`@Query`/services, no ViewModel) per tech-design §2.1; the collapse state is trivial local `@State`, which stays below the VM-escalation bar.

## Goals / Non-Goals

**Goals:**
- Detail title renders icon (leading, decorative) + name, mirroring correctly in LTR and RTL.
- Long names wrap to full multi-line display in the expanded state.
- The expanded large title collapses/merges into an inline nav-bar title (icon + truncated name) on scroll, with large-title size/weight typography preserved in the expanded state.
- VoiceOver announces the name only; the title carries the `.isHeader` trait.
- Typography matches the standard SwiftUI screen-title look (large-title, bold, Dynamic Type), wrapping instead of truncating.

**Non-Goals:**
- Pixel-perfect reproduction of UIKit's large-title morph animation. We approximate the system crossfade with an opacity transition; we do not reimplement the navigation bar.
- Changing the Budgets list row, the Add/Edit picker chip, or any other screen's title.
- Any data-model, persistence, sync, string-catalog, or analytics change.

## Decisions

### D1 — Render the title as the first `List` row, not `navigationTitle`

Set `.navigationBarTitleDisplayMode(.inline)` and drop `.navigationTitle(...)`. Add a new first `Section` containing the large-title header (clear row background, hidden separator, leading-aligned insets that match the system large-title leading margin). This is the standard SwiftUI technique for a custom, wrapping, scroll-aware large title: the header scrolls with the content and disappears under the (now inline) nav bar.

*Alternatives considered:* (a) keep `navigationTitle(String)` with `.large` mode — rejected: can't wrap or place the icon as a leading view, the exact problems we're fixing. (b) `safeAreaInset(edge: .top)` overlay — rejected: pinned, would not scroll away. (c) a `LabeledContent`/`Text` with attributed-string icon — rejected: an inline image attachment still doesn't mirror like `HStack` layout and complicates VoiceOver.

### D2 — Icon as a leading `HStack` view, reusing the list-row idiom

The header is `HStack(alignment: .firstTextBaseline, spacing: 0) { if icon { Text(verbatim: "\(icon) ") }; Text(budget.name) }`, exactly mirroring `BudgetRowView.nameText`. The trailing space baked into the icon text reproduces the single-space gap, so `spacing` is 0. `HStack` mirrors with layout direction, putting the icon on the right in RTL — the core bug fix. Styled `.font(.largeTitle).fontWeight(.bold)`, `.multilineTextAlignment(.leading)`, `.frame(maxWidth: .infinity, alignment: .leading)`, with wrapping (no `lineLimit`).

`budget.iconPrefixedName` (the string form) loses its only production caller. Keep it for now if tests reference it; otherwise it can be removed in this change. Decided in tasks after checking callers.

### D3 — Scroll tracking via measured header height + `onScrollGeometryChange`

The collapse threshold depends on the wrapping header's height, which varies with name length and Dynamic Type. Measure it with `onGeometryChange(for: CGFloat.self) { $0.size.height }` on the header and store it in `@State`. Apply `.onScrollGeometryChange(for: Bool.self)` to the `List`, computing `geo.contentOffset.y + geo.contentInsets.top > collapseThreshold` where `collapseThreshold` is a fraction (~0.6) of the measured header height — i.e. collapse once most of the large title has scrolled under the bar. Drive a `@State var showInlineTitle` from the action closure inside `withAnimation(.easeInOut)`.

*Alternatives considered:* a `GeometryReader` sentinel comparing the header's global `maxY` to the top safe-area inset — workable but more fragile across safe-area/coordinate-space edge cases than reading the scroll geometry directly. `ScrollViewReader`/preference keys — heavier and chattier than the dedicated iOS 18+ scroll-geometry API.

### D4 — Inline collapsed title as a `.principal` toolbar item

With inline display mode and no `navigationTitle`, the nav-bar center is empty, so a `ToolbarItem(placement: .principal)` owns it. It renders the same icon-leading `HStack` (icon decorative + name) but `.lineLimit(1)` truncating, `.font(.headline)` to match the system inline title weight, and `.opacity(showInlineTitle ? 1 : 0)` (always present, animated opacity) so it crossfades in as the content title scrolls away — keeping the icon on the leading edge even in the bar, per the issue. Always-present + opacity is more reliable than inserting/removing a toolbar item via `if`.

### D5 — Accessibility

The content header: `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(budget.name)` + `.accessibilityAddTraits(.isHeader)` so VoiceOver reads the name only (icon decorative) and treats it as the screen heading — consistent with the list row, which omits the icon from its label. The inline principal title is also name-only; when both are effectively visible to AX, the header is the canonical heading. The status-header remaining-summary keeps its existing `.isHeader` trait; a second header (the screen title) is expected and correct.

## Risks / Trade-offs

- **[Approximated collapse vs. system morph]** → The crossfade is an opacity transition, not UIKit's geometric morph. Acceptable per Non-Goals; visually reads as the title merging into the bar. Tune duration/threshold during implementation.
- **[Threshold jitter near the collapse point]** → A single boolean threshold can fl/flop if scroll hovers exactly at the boundary. Mitigate by collapsing at ~0.6× header height (well past the boundary) and animating, so small jitter isn't visible; add hysteresis only if testing shows flicker.
- **[`onScrollGeometryChange` on `List`]** → `List` is backed by a scroll view, so the modifier applies, but `contentInsets`/`contentOffset` semantics differ from a bare `ScrollView`. The threshold formula uses `contentOffset.y + contentInsets.top` (0 at rest) to stay robust; verify on-device and in previews.
- **[Large-title leading margin alignment]** → A list row's leading inset may not exactly equal the system large-title margin. Set explicit `.listRowInsets` to match and verify against the (former) system title position; cosmetic, not behavioral.
- **[Dropping `iconPrefixedName`]** → If removed, ensure no test or other surface still calls it. Checked in tasks.

## Doc alignment

- `docs/tech-design-doc.md` §2.1 — aligned: stays a no-ViewModel View; collapse state is trivial local `@State`.
- `docs/main-prd.md` — aligned: reinforces HIG, Dynamic Type, RTL/i18n.
- `docs/product-features-planning.md` F-4.03 — wording update: the detail title renders the icon as a leading **view** (RTL-correct), not a string prefix. Tracked as a task.
