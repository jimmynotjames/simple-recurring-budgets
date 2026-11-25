Closes #N

## What
*

## Why


## Test plan
- [ ]

## Tools
-

---

## Cross-cutting concerns (PRD §6.8)

For any UI-touching change, confirm each applies-or-N/A:

- [ ] Accessibility (Dynamic Type + VoiceOver)
- [ ] Dark Mode (named color assets)
- [ ] Localization — source strings keyed + 49 locales translated
- [ ] Mixpanel user-action analytics
- [ ] UI test screen objects updated

---

### 🧪 Running tests

CI auto-runs lint, secret scan, translation/localization gates, a compile
check, and the **full unit + UI suite (accessibility + user-journey)** on
every PR. To start a run on this PR, comment `/ci` with the words to run (the
repo owner's comments only; `/ci help` lists them), e.g. the UI suite:

```
/ci ui
```

or one class or test three times (e.g. after a flaky failure):

```
/ci test simple-recurring-budgetsUITests/UserJourneyTests x3
```
