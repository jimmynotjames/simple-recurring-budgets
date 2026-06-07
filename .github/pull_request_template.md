<!-- Brief summary of what this PR changes and why. -->

## Summary

-

## Cross-cutting concerns (PRD §6.8)

For any UI-touching change, confirm each applies-or-N/A:

- [ ] Accessibility (Dynamic Type + VoiceOver)
- [ ] Dark Mode (named color assets)
- [ ] Localization — source strings keyed + 49 locales translated
- [ ] Mixpanel user-action analytics
- [ ] UI test screen objects updated

---

### 🧪 Running tests

CI auto-runs lint, secret scan, translation gates, a compile check, and the
**unit tests**. The full **UI suite (accessibility + user-journey)** is *not*
automatic — to run it on this PR, comment:

```
/test-full
```
