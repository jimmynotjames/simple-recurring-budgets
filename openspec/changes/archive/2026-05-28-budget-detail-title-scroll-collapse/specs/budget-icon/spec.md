## MODIFIED Requirements

### Requirement: Icon display on the Budget detail screen

On the Budget detail screen, the budget title SHALL render the budget's icon (when set) as a **leading view** preceding the budget name — not as a string prefix — so the icon sits on the leading edge and mirrors with layout direction (right edge in RTL), consistent with the Budgets list row. When no icon is set, the title SHALL render the budget name alone. The icon is decorative and SHALL NOT be announced by VoiceOver. (The full title behavior — wrapping and scroll collapse — is specified by the "Scroll-aware content-area budget title" requirement in the budget-detail-screen capability.)

#### Scenario: Detail title with an icon

- **WHEN** the Budget detail screen is shown for a budget that has an icon
- **THEN** the title SHALL render the icon as a leading view, followed by the budget name, with the icon on the leading edge in both LTR and RTL

#### Scenario: Detail title without an icon

- **WHEN** the Budget detail screen is shown for a budget with no icon
- **THEN** the title SHALL render the budget name alone, with no leading icon view
