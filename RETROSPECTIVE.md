<!--
  RETROSPECTIVE.md — a first-person essay, not a sprint retro.
  Think "Medium post about building Wren," not "what went well / what went poorly / action items."
  Every section below is a PROMPT for you to write prose. Delete the hints as you fill each in.
  Keep your voice. Show the seams — the honest version is more interesting than a victory lap.
-->

# Building an App Where AI Wrote (Almost) Every Line

*An essay on building **Wren**, a production-bound iOS app, through agentic AI development.*

> ✍️ **Subtitle / dek (1–2 sentences).** The hook a reader sees under the title. Suggested angle: "I set out to write none of the code myself — and ended up doing the most important engineering of my career." Land the tension: less typing, more thinking.

---

## The premise: two lines of human code

> ✍️ Open with the striking fact and the rule you set yourself.
> - The constraint: AI writes 100% of the code; you only direct. Exactly two lines ended up hand-written — what were they, and why were they the exception? (Great concrete cold-open.)
> - What "agentic" meant in practice vs. autocomplete/copilot: agents that plan, edit across files, run tools, and open PRs.
> - Set expectations for the reader: this isn't a "look ma, no hands" piece — it's about *where the human work moved to*.

## Why I did this

> ✍️ Motivation. A few honest reasons.
> - Career/skills bet: agentic AI is changing how software gets built; you wanted real reps on a non-trivial, shippable app — not a tutorial to-do list.
> - Why a *budgeting* app specifically (small, well-bounded domain; real-but-tractable complexity in the carry-over math; a genuine product wedge you cared about).
> - What you were trying to prove (to yourself, to employers): that you can *direct* AI to a real App Store release with engineering rigor intact.

## Where the real work went: specs, not syntax

> ✍️ The thesis of the whole piece. This is the section that separates you from "I vibe-coded an app."
> - The hardest, most manual work was the **PRD** ([`docs/main-prd.md`](docs/main-prd.md)) and **UX brief** ([`docs/ux-design-brief.md`](docs/ux-design-brief.md)) — drafted by hand to govern every downstream agent decision.
> - The mental shift: from "how do I implement X" to "how do I *specify* X unambiguously enough that an agent gets it right." Ambiguity in the spec = bugs in the code.
> - The leverage insight: time spent sharpening the prompt/plan/spec paid back many times over the build. A vague ask got vague code.
> - Optional: a before/after micro-example — a fuzzy instruction that produced wrong code, vs. the tightened version that worked.

## Imposing discipline on the agents

> ✍️ How you kept quality from depending on any single lucky generation.
> - **OpenSpec**: why a spec-driven change workflow mattered for agents specifically — proposals, deltas, and a paper trail that constrains scope. ([`openspec/`](openspec))
> - **`AGENTS.md`** as the canonical rulebook every agent reads — build/test gates, concurrency rules, cross-cutting-concern checklists (a11y, localization, analytics, UI-test screen objects).
> - **CI gates agents can't bypass** — lint, secrets scanning, i18n gates, build, tests. The machine enforces what a skim review might miss.
> - The meta-point: you treated the agents like a fast, tireless, slightly-overconfident junior team — and built guardrails accordingly.

## My build order: foundation first, UI last

> ✍️ Tell the sequencing story — it's a real engineering decision and reads well.
> - **Data model first** (the four SwiftData entities: Budget, ExpenseItem, AllocationChange, LifecycleEvent).
> - **Then the calculation core** — the pure `Domain/` services (`PeriodCalculator`, `BudgetCalculator`, the carry-over "live walker") with tests, before any screen existed.
> - **Then vertical feature slices** on top — each feature cutting through model → service → view → tests.
> - Why this order suited AI development: a tested, pure core gave agents a stable contract to build against and made their UI work verifiable.
> - Optional: where you deviated from the plan and what that taught you.

## The tooling tug-of-war: Cursor vs. Claude Code vs. Xcode

> ✍️ The "experimenting between tools" story. Be specific and fair.
> - What each was good at: Cursor (…), Claude Code (…), Xcode/its own AI (…). Where each frustrated you.
> - How you split work between them — and the friction of keeping config in sync (e.g. mirroring agent instructions/skills across Cursor and Claude Code).
> - The reality that the *IDE* and the *build/simulator loop* are still where agentic dev hits friction on Apple platforms.
> - Where you landed, and what you'd reach for next time.

## The audit habit

> ✍️ Your "semi-regular audits" practice — a genuine differentiator worth its own section.
> - Why AI-generated code *especially* needs periodic audits: drift between docs and code, silent regressions, plausible-but-wrong implementations.
> - The cadence and types: accessibility, code quality, localization + VoiceOver, code-vs-doc drift, test coverage, architecture. (See [`docs/audits/`](docs/audits) — point to it as evidence.)
> - A war story: an audit that caught something a normal review wouldn't have.
> - How auditing became your main "review" surface as code volume outpaced line-by-line reading.

## Where AI struggled

> ✍️ The honest counterweight. This section earns the reader's trust.
> - Concrete failure modes: confidently-wrong logic, subtle date/timezone or money-rounding bugs, fabricated APIs, over-engineering, doc/code drift, churn on the same problem.
> - Anything Apple-platform-specific that tripped agents up (Swift 6 concurrency, SwiftData+CloudKit quirks, XCUITest, simulator flakiness).
> - How you caught these (tests, audits, the two hand-written lines?).
> - What still required a human brain, full stop.

## What surprised me

> ✍️ A short, punchy list or a couple of paragraphs.
> - Something that worked far better than expected.
> - Something you assumed AI would nail that it didn't.
> - How your own role/skills changed by the end.

## Would I do it again? / What this means for how I work

> ✍️ The closer. Reflective, forward-looking.
> - Honest verdict on the 100%-AI constraint: worth it as an experiment? What would you keep vs. relax on the next project?
> - What it taught you about the future of the engineer's role — spec author, reviewer, architect of guardrails.
> - The takeaway you want a hiring manager or fellow engineer to leave with.

---

## Appendix: by the numbers

> ✍️ Optional but great for credibility — fill from the README's "at a glance" stats and your own records.
> - Timeframe (start → first TestFlight/App Store).
> - ~Swift files / tests / locales / PRs / OpenSpec changes / audits run.
> - Direct dependencies (one), and the deliberate near-zero-dependency stance.
> - Anything else quantifiable that tells the story.

*See also: [`README.md`](README.md) for the project overview, [`ARCHITECTURE.md`](ARCHITECTURE.md) for the engineering design, and [`docs/`](docs) for the PRD, UX brief, and audits.*
