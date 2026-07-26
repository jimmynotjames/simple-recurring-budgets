# Retrospective: Adventures in Agentic Coding

> This document covers my efforts from inception to deployment of the first version of this app. April-July, 2026. I manually wrote and edited this document with AI serving as copyeditor.

## Contents

* [Introduction](#introduction)
  * [Background and Context](#background-and-context)
* [What Was Accomplished](#what-was-accomplished)
  * [Concepts Explored / Skills Practiced](#concepts-explored--skills-practiced)
  * [High-level Project Timeline](#high-level-project-timeline)
  * [Repo stats](#repo-stats)
* [Governing Docs](#governing-docs)
  * [Product and UX Design](#product-and-ux-design)
  * [Technical Architecture](#technical-architecture)
* [Tools, Models, Costs](#tools-models-costs)
  * [AI tools used](#ai-tools-used)
  * [Cost breakdown (April - July 2026)](#cost-breakdown-april---july-2026)
  * [End-State Agentic Tooling Set-up](#end-state-agentic-tooling-set-up)
* [Lessons Learned](#lessons-learned)
  * [Comparing Models and Harnesses](#comparing-models-and-harnesses)
  * [Other Coding Lessons](#other-coding-lessons)
  * [Xcode and Simulators and Sandboxes, oh my!](#xcode-and-simulators-and-sandboxes-oh-my)
* [Larger Themes and Insights](#larger-themes-and-insights)
  * [The Importance of Good Product and Design Thinking (or "Taste")](#the-importance-of-good-product-and-design-thinking-or-taste)
    * [Discernment versus speed](#discernment-versus-speed)
    * [80:20 Rule as applied to taste?](#8020-rule-as-applied-to-taste)
  * [Garbage In; Garbage Out](#garbage-in-garbage-out)
  * [Agent-readable Versus Human-readable](#agent-readable-versus-human-readable)
  * [Do Deterministic Things Deterministically](#do-deterministic-things-deterministically)
* [In the End, Did AI Agents Make Me a Better Developer?](#in-the-end-did-ai-agents-make-me-a-better-developer)
  * [Efficiency gains](#efficiency-gains)
  * [Multiple autonomous agents](#multiple-autonomous-agents)
* [Would I Do This Again?](#would-i-do-this-again)

## Introduction

I built this app to learn agentic coding. To do that, I set out to create a useful product with an elegant, efficient user experience. Learning new iOS concepts was a nice-to-have along the way. What was *not* a priority: earning revenue or aggressively growing downloads.

### Background and Context

These influenced my product, UX, and technical choices:

* 20+ years in the software industry ([LinkedIn](https://www.linkedin.com/in/jimmynotjames/)). I'm a software engineer by profession and training. Sc.B. and Sc.M. in Computer Science. Early years doing full stack on JavaServer Pages + Java Enterprise Edition.
* Self-taught iOS c. 2010. Published my first app in 2012.
* Over the years, I have both published my own apps and found full-time employment working on a very large enterprise iOS codebase. At the time of this writing, I still work on that codebase, now with agentic tools.
* Excluding this app, I published three of my own apps over the years, two of which are still in Apple's App Store.
* I have a day job and life outside of engineering, so I have limited time and money to produce this app and maintain it over the long arc of time. Long-term maintainability with minimal effort is important.
* I'm mission-driven, so, to find motivation, I wanted to create a good product that I could be proud of and deploy it to production. I also wanted my AI learnings to apply to my professional life working on enterprise systems, so producing a "toy app" felt lacking.

## What Was Accomplished

AI agents produced all code, including Swift, Python, shell scripts, and config files. AI agents also produced UI mock-ups through SwiftUI Previews or Figma that informed the UI/UX. AI produced the app icon.

Exceptions:

* Core app and localizations scaffolding. Produced via Xcode's canonical UI flows. 
* App provisioning and signing. Xcode UI again.
* Two lines of SwiftUI code that I copy-pasted in after getting frustrated with Xcode's agent early on in this journey.

Along the way, AI agents also:
* Discussed with me product, UI/UX, and technical architecture decisions.
* Reviewed code, including all code in later phases. I at least skimmed most PRs, with in-depth reviews of code updates I thought were significant.
* Set up skills and commands for autonomously(ish) fixing issues, generating PRs, and merging them. These include extra code review, CI/CD gates, and generally enforce discipline on the coding workflow. ([/create-pr-for-issue](.claude/skills/create-pr-for-issue/SKILL.md), [/create-pr](.claude/skills/create-pr/SKILL.md), [/merge-pr](.claude/commands/merge-pr.md))
* Generated, reviewed, and edited documentation. This included using Fission's OpenSpec tool.
* Conducted all manner of audits of code and documentation, and syncing the two.
* Eyeballed sample screenshots qualitatively for Dynamic Text and translated text truncation. ([/translation-accessibility-size-check](.claude/skills/translation-accessibility-size-check/SKILL.md))
* Designed and implemented OSLogger and Mixpanel analytics, including using Mixpanel MCP to generate dashboards.
* Translated app text copy for 49 App Store locales. ([/translate-new-strings](.claude/skills/translate-new-strings/SKILL.md))
* Translated App Store metadata/marketing copy for 49 App Store locales. ([/appstore-translate-metadata](.claude/skills/appstore-translate-metadata/SKILL.md))
* Generated 500 screenshots in all App Store locales, generating culturally sensitive example data (local currency, currency amounts, budget topics). ([/appstore-generate-screenshot-seeding](.claude/skills/appstore-generate-screenshot-seeding/SKILL.md), [/appstore-generate-push-screenshots](.claude/skills/appstore-generate-push-screenshots/SKILL.md))
* Generated complex, custom pipelines and jobs, like mentioned above, along with setting up CI/CD, writing iOS simulator sandboxing scripts, App Store deployment scripts, etc. ([/ios-sims](.claude/skills/ios-sims/SKILL.md), [/appstore-push-testflight-build](.claude/skills/appstore-push-testflight-build/SKILL.md))
* Deployed the CloudKit Production schema for the first time (a practically irreversible operation — fields can be added but never removed once live) via a new, safety-first skill built mid-release, with mandatory audit/confirmation gates and an Opus-tier model requirement given the stakes. ([/cloudkit-deploy-schema](.claude/skills/cloudkit-deploy-schema/SKILL.md))
* Generated custom agent skills, commands, and configurations to work more autonomously and effectively within the context of this repo and project. ([.claude/skills/](.claude/skills), [.claude/commands/](.claude/commands), [.claude/settings.json](.claude/settings.json))

### Concepts Explored / Skills Practiced

* Creating and managing agent skills, commands, permissions, and other configuration settings.
* Multi-step agent workflows
* Agent context management
* Token cost efficiency
* AI-generated dashboards with Mixpanel MCP
* App Icon design with Figma AI and Claude Design.
* Prototyping UI layout design with Figma AI and Claude (all varieties). 
* Custom translations/localizations pipelines

### High-level Project Timeline

April - July 2026

1. Product spec drafting
2. App scaffolding, repo infra, etc.
3. Design and implement database model layer for most of feature set
4. Design and implement budget calculator algorithm for most of feature set
5. Design and implement screens and features
6. Iterate and improve
7. App Store admin and packaging
8. Submit to App Store and deploy

Threaded through that:

* Implementing/refining localization/translations pipelines
* Adding/updating skills and infrastructure (CI/CD, etc.)
* Full-repo audits by agents for architecture, accessibility, localization, general bug checking, etc. (See [docs/audits](docs/audits/))
* After screen UI flows were mostly stable, added UI tests
* Constantly configuring my agents and refining my prompting to improve their work.

Overall, I'm happy with how this went. While designing the database and calculator layers felt tedious because I didn't see a single screen rendered for weeks, I felt it was better for agents to produce a complete data model and algorithm rather than refactor/rewrite over time as I added features.

### Repo stats

| Type                       | Count                      |
| -------------------------- | -------------------------- |
| Swift                      | ~27k lines                 |
| Python                     | ~7k lines                  |
| Shell scripts              | ~1k lines                  |
| Custom AI skills/pipelines | 14                         |
| GitHub PRs merged          | 250+                       |
| Locales supported          | 49 (all App Store locales) |



## Governing Docs

### Product and UX Design

Agents read [main-prd.md](docs/main-prd.md), [product-features-planning.md](docs/product-features-planning.md), and [tech-design-doc.md](docs/tech-design-doc.md) before any task, along with [ux-design-brief.md](docs/ux-design-brief.md) for UI-related work. They help my agents make decisions by providing higher purpose and direction.

I hand-wrote [main-prd.md](docs/main-prd.md)'s first sections, including Vision, Problem Statement, Guiding Principles, Goals, and User Personas. Agents appended more over time. I also rewrote parts of the doc as I iterated through UI features and refined my product thinking. 

I manually wrote [product-features-planning.md](docs/product-features-planning.md) to start. This doc helped agents understand how to design and implement current features that were extensible for future improvements. Agents heavily edited the doc over time. I occasionally edited future features as the product evolved.

Claude Opus and I co-authored [ux-design-brief.md](docs/ux-design-brief.md), using `main-prd.md` as input, with heavy manual editing. Agents then made more edits as the project went on.


### Technical Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) and [tech-design-doc.md](docs/tech-design-doc.md). Claude Opus and I initially co-wrote both. Agents then revised them over time at my direction.



## Tools, Models, Costs

### AI tools used

* Claude Code CLI
* Claude Code on Claude Desktop
* Cursor (~v3.8) + Claude
* Cursor + Composer (v2, v2.5)
* Xcode (v24.4, v24.5) + Claude
* Figma AI (Visual design only)
* Claude Design (Research Preview) (Visual design only)
* Fission's [Open Spec](https://github.com/Fission-AI/openspec) AI Skills for spec-driven development (SDD) (product-level features only)

Claude models used in all of the above tools: Fable 5, Opus 4.8, 4.7; Sonnet 4.6; Haiku 4.5. 
Only a few PRs resulted from Fable 5 due to Anthropic pulling it after a few days.

### Cost breakdown (April - July 2026)

| Tool or Service | Cost (USD) |
| -- | -- |
| Claude (Pro and Max 5x subscriptions April-July, plus extra usage tokens) | $248.36 |
| Claude API tokens from Xcode                                 | $53.75     |
| Claude API tokens from Cursor                                | $349.68    |
| Claude Design Research Preview                               | -$0-       |
| Cursor Pro subscription                                      | $87.12     |
| Figma AI (subscription + extra token purchase)               | $38.99     |
| Apple Developer Account*                                     | $107.79    |
| Mixpanel Growth Tier**                                       | -$0-       |
| Privacy Policy via TermsFeed.com (one-time fee)              | $79.50     |
| Annual Insurance Premium*                                    | $446.00    |

\* Covers all the apps I've produced. 
\** I got Mixpanel's "Growth" tier to get unlimited reports, but first million analytics events are free, and I don't expect to exceed a million in a month. If I do, it's a good problem to have! (Or an infinite loop in my code!)

### End-State Agentic Tooling Set-up

By the end of this project, my developer environment consisted of:

* Primary agent: Claude Code CLI with Max 5x subscription ($100+tax/month)
* Updating markdown docs and occasional agent coding use: Cursor Free tier; Typora.
* Visual design: Claude Design




## Lessons Learned

### Comparing Models and Harnesses

Harness makes a big difference. Despite using the same underlying Claude LLMs, Cursor, Xcode, and Claude Code behaved in different ways, from the way they managed context to UI layout decisions to coding competency. Compared to enterprise apps, this was not a complex project, so the differences in competency were minor, though.

I started with Cursor because I wanted to see the code being generated. I would run out of my Cursor monthly subscription in a few hours and then need to meter my tokens for the rest of the month. Even as a side project, over time, my token usage became expensive.

Claude first-party subscriptions renew token allocations every 5 hours and weekly, and this was much more preferable, especially once I changed to Claude Max. In the end, first-party Claude was more economical. Xcode is still far behind and its agents proved to be buggy and not useful except in niche cases.

From a pure competency perspective, I preferred Claude Code CLI using Claude Opus 4.8, which was the highest Opus version available at the time.

One Cursor feature I miss is the ability to change models mid-conversation without having to reload the prompt cache. While I prefer Claude overall I didn't like that it had to reload the entire conversation context (or compact/summarize, which also has costs) when changing models. So if I started on Opus and wanted to switch to Sonnet for a lesser task, I was left guessing the token-usage tradeoffs. 

Cursor was also more forgiving about permissions. Claude Code was very fussy, and it's absurd the number of times I invoked `/fewer-permission-prompts`, implemented hygiene rules, and had Claude write shell scripts or Makefile targets just to get around permissions issues. However, once I got my harness in a decent place, agents could mostly work autonomously.

Cursor's Composer 2.5 model was generally competent at core coding tasks, but it seemed to lack the higher level reasoning skills that Opus was capable of. It was the cheapest model I used though, and often best value for money when the coding task was extremely straightforward. 

Figma AI produced the most beautiful color palettes, and I used one of them in the current app design. One of its proposed layouts also ended up being the template for the main screen.

When it came to producing Apple-native-looking, elegant UI layouts, Xcode + Claude often did the best job, but was inconsistent. With some guidance, Claude Code CLI did a great job as well. 

I used Figma AI and Claude Design to produce app icon candidates. Using my [main-prd.md](docs/main-prd.md) and [ux-design-brief.md](docs/ux-design-brief.md) as attachments, I had Claude Opus generate detailed prompts tailored for both tools and compared the results. Creatively, both outputs informed my subsequent turns on both tools. In the end, Claude Design won with the app icon that best suited my needs. I should also note that Claude Design was great at outputting the app icon in Icon Composer's special 4-layer SVG format, whereas I could never figure out how to get Figma AI to do the same. Caveat: I'm not a skilled Figma user nor a graphic designer.

### Other Coding Lessons

**Agents should review first.** For example, my `/create-pr` skill has a step that spawns a subagent with fresh context to do one final code review, in case I forgot. 

I also run full-repo code audits every several weeks to detect issues (see [docs/audits/](docs/audits/)). These audits helped me discover numerous useful things, like Apple's accessibility audit function and that Claude can eyeball screenshots for me to check for accessibility issues. 

Laughably, I discovered Claude's /code-review skill too late to use on this first app version. 

**Explicitly ask for architecture reviews.** Agents tend not to be as concerned about architecture as I would have liked. I tried to explicitly discuss architecture with Opus before starting any feature or code refactor, even if I thought the task was straightforward. Also ran full repo architectural audits every several weeks. This helped me catch deeper issues before they got out of hand.

**Pay more attention to core algorithms.** Alas, I rewrote the budget algorithm midway through the project, which was a major effort. On the first go-around, both Claude Opus and I failed to notice a basic edge case where a user adds a new ExpenseItem and backdates it to a prior Period. Agents didn't later catch this bug; I did. This, despite multiple audits and code reviews. 

We discovered more algorithm flaws as we dug deeper; it was a mess. It spawned a very large rewrite effort, which is documented in [budget-calculations-rewrite-algorithm.md](docs/budget-calculations-rewrite-algorithm.md), [budget-calculations-rewrite-reqs.md](docs/budget-calculations-rewrite-reqs.md), and [budget-calculations-rewrite-migration-prompt.md](docs/budget-calculations-rewrite-migration-prompt.md).

### Xcode and Simulators and Sandboxes, oh my!

Apple's iOS Simulators do not have a clear concept of a sandbox. I'm not talking about within each Simulator; that's obviously a proper sandbox. I'm referring to the collection of Simulator instances on my Mac. They just run on the computer like any other app on a Mac and cannot be sandboxed unless you run separate Mac instances. At some point, I had three repo clones, each with an agent sometimes spawning simulators to run tests, and on top of that, I was launching Simulators from Xcode to do manual testing. That was not a good idea.

I lost ~$50 in tokens one afternoon as I neglected to notice two agents fighting over one Simulator instance for hours. They didn't know why their tests were failing, and each one would try to diagnose, retry, etc. but would interfere with each other's efforts. I was distracted by something else that afternoon, so I absent-mindedly said yes to, say, agent prompts asking me to `pkill` a Simulator to reset it, causing the competing agent's tests to fail. Ugh. After that, I implemented some custom skills and scripts to put a stop to that.  

By the way, this was partly self-inflicted. Early on, when I only had one repo clone, I got impatient with how slow it took to launch Simulators to run tests. I updated my harness to run scripts to reuse whatever Simulators were already launched. As I expanded to multiple agents, they all ran that same script and tried to reuse the same Simulators. :man_facepalming:



## Larger Themes and Insights

### The Importance of Good Product and Design Thinking (or "Taste")

I published my second app in December 2012 and as of June 2026, it still has a 4.4 average star rating to this day! ([Army Leader Book App](https://apps.apple.com/us/app/army-leader-book/id583674365)) I noted at the time that, while my engineering skills were enough to make a stable, working app, what made it the canonical app used by Army sergeants to this day was my product management skills and domain knowledge. Having spent years as an Army Reserve sergeant, I had extensive domain knowledge and an extensive network to tap to get app feedback. 

Thus, for this app, I spent a lot of time crafting my product spec and using the product myself. Every other governance document, agent decision, architectural choice, etc. has stemmed from my [main-prd.md](docs/main-prd.md). 

I spent 1.5 days writing the first draft of the [main-prd.md](docs/main-prd.md) and [product-features-planning.md](docs/product-features-planning.md), and this upfront investment in thinking about my product was one of my best decisions of this project. 

A few weeks into the project, I spent a few hours over a few days rewriting major sections of the docs. As a writer, I think this is important beyond instructing agents. The act of hand-writing the product spec clarifies my product thinking and sharpens my taste and judgment. 

When I think about what I should be hand-writing versus letting the agent write, this is one of the things that should be hand-written.

#### Discernment versus speed

One major limitation to the autonomy and speed of my agents was my ability to specify exactly the UI/UX I wanted. I'm not a UX designer or graphic designer. I needed to mock things in Figma AI or prototype with Claude, Xcode, etc., then see the Swift Preview or interact with the UI in the simulator before I could make a decision. 

Certainly, I found it gratifying to quickly prototype UIs in code instead of mock-up/graphic design tools. I quickly ramped off of Figma because of that. For example, I would ask Cursor or Claude to spawn three versions of a screen update, and come back 10 minutes later with three Swift Previews to view.

That said, I didn't see a viable way to tell an agent to give me everything exactly the way I would have wanted it upfront because I often didn't know myself. Rounds of iteration were necessary, including days or weeks where I used the app in my daily life to discover UX issues. At least I'm comforted that at my enterprise job, the UX designers and product managers also need to iterate to find their way to a viable product. 

Again, this is where "taste" or "judgment" comes into play. I have a specific point of view, and it's not clear to me how I can mind-meld with the AI in such a way that it can autonomously exercise the same discernment that I have, and produce this app autonomously. Sure, I had my governing PRD and UX documentation, but they weren't enough to cover everything. 

#### 80:20 Rule as applied to taste?

Also known as the [Pareto Principle](https://en.wikipedia.org/wiki/Pareto_principle). I first learned this in leadership: that I would spend 80% of my time on 20% of my team members or issues. 

As AI agents shrink the work that's easy to do, the application of "taste" will likely become the dominant 80% of the effort to produce that last 20% that differentiates AI slop from a quality product. Haha, or, at least, a product with character! Something that clearly shows it's authentic to a specific person's vision.

I can see this on my own app. But for a few UI tweaks here and there, say 20% of it, my app could easily appear like a generic app with generic features, generic layouts, and generic color palettes. (Honestly, to a lot of users, it probably does appear generic, as I tried to keep to most Apple HIG and industry-standard idioms, with minimal "weird" layouts that might break or look weird in future OS versions.)

### Garbage In; Garbage Out

The more I work with AI, the more this old computer science adage keeps coming up for me. All software ultimately involves inputs and outputs, and garbage input encourages garbage output. 

In my day job, my enterprise iOS codebase has files dating back to the inception of the Apple App Store (2008!). There are a gazillion outdated coding patterns and vague code comments, and I find that agents can get confused by this old "garbage" input unless I redirect them.

Thus, after the above experiences, I feel that writing thoughtful prompts and giving the agent accurate and complete context are more important than ever. 

In line with this, as an example, I ran audits every several weeks to catch any syncing issues between my specs and code, to tighten any drift. And to be clear, my core workflow included syncing docs, as part of openspec or in my agent configs. And yet, despite these safeguards, these audits definitely caught issues. 

Without these audits, in the best case, the agent wasted tokens trying to reason out the context; in the worst case, agents introduced bugs or regressions. In the future, I might consider a CI/CD job or background agent that continually re-reviews for drift, depending on token costs.


### Agent-readable Versus Human-readable

While subtle, it's important to be clear on whether an agent or human or both will read a piece of code or documentation. This informed how I directed my agents and how I reviewed documents and code.

By "agent-readable", I really mean "agent readable AND human-skimmable". I still would like some idea what's happening, but I don't need to go deep.

There were times when the agent tripped over something, and I instructed it to insert a code comment or update a guidelines document with something "...for future agents". I didn't nitpick over the wording or verbosity because I was not the primary audience. 

When I'm writing something that I or another human will read, I will often hand-write it or instruct the agent to be "concise" and write for humans.

As an example, I implemented analytics in a nonchalant fashion. Having well-tuned analytics schemas was not important for this small, free app, so I had agents write an [analytics-spec.md](docs/analytics-spec.md), prompting them to keep things simple and follow industry best-practices. 

I only skimmed it enough to make sure the agent didn't go off the rails. I couldn't care less if it wanted to measure Monthly Active Users or Monthly Sessions or whatever other subtle distinctions might matter more for an enterprise app. So I generally left the doc alone, and used it as input to design and implement the analytics in code, and then later to connect to Mixpanel MCP to create the dashboards. 

None of this required the docs and code to be human-readable, so I didn't bother to try to manually refine them. What was important to me was my desired end state, which was to have some basic monitoring and user behavior logging in place to inform future features and detect issues. 

### Do Deterministic Things Deterministically

Whatever can be checked deterministically, check it with code, not LLMs. Usually a Python or shell script in my case. This principle is not mine. I first learned this from an IBM tech talk at New York Tech Week 2026. This project reinforced that advice repeatedly. 

As I continued to develop features, I grew more and more frustrated with the non-deterministic nature of LLMs in certain use cases, and started instructing my agents to write deterministic checks. For example, I now have scripts to verify that all strings are localized and translated before pushing every PR. I started using Apple's [XCUIApplication.performAccessibilityAudit()](https://developer.apple.com/videos/play/wwdc2023/10035/) to audit accessibility issues. And so on.

## In the End, Did AI Agents Make Me a Better Developer?

### Efficiency gains

Given that I have 10+ years of iOS experience, it's unclear to me if AI agents helped me create the core features of my app faster than if I hand-wrote those parts (AI would have still reviewed my PRs, though). This includes the core budget calculations engine and core UX flows.

However, AI did help me create a higher-quality, more inclusive and maintainable app, in probably a tenth of the time it would have taken me to do those extra tasks manually. And I wouldn't have even bothered with much of it, due to lack of expertise and time to properly design and implement.

Here are features and aspects that AI helped realize:

* Extensive automated tests, including UI tests and accessibility audits
* Robust Mixpanel analytics, including autonomously generating the dashboards in Mixpanel for me.
* CloudKit syncing of my SwiftData, so users can sync their budgets across multiple devices
* Localizations for all supported languages/locales. This includes marketing copy in the App Store, example budgets to populate the localized App Store screenshots, and of course, app text translations. All culturally sensitive, with a common translations glossary for key terms, and plural forms properly rendered.

I definitely found value in AI reviewing itself. Having a second set of (agentic) eyes on this code was much appreciated. It's not easy to find another iOS developer with time and expertise to review my code for no pay for an app with no commercial intent.

### Multiple autonomous agents

For a product and repo of this size, I found it very hard to get beyond three simultaneous agents, with each agent on a separate cloned repo. And at that limit, I was making mistakes and mixing up context. I usually found two agents to be my sweet spot. My tasks typically lasted 3-10 minutes, certainly never more than 30 minutes, unless I was capturing App Store screenshots (2+ hours). 

Having to constantly bop around checking on the agents took its toll. Especially early in my journey as I hadn't smoothed out my permissions nor refined how I prompted and managed context.

That said, I suspect I'll find ways to manage my personal context more effectively over time, while simultaneously configuring my agents to require less ongoing guidance from me. Not to mention the continuing, rapid improvements to models and harnesses by the AI companies. 

For an app of this size and my limited time for side projects, I felt that I pushed agent autonomy as far as I could while maintaining high quality standards. I just didn't have time to set up a multi-agentic, multi-agent-role workflow. And I didn't think I could keep up with the flow, given the time I could devote to this project. 



## Would I Do This Again?

Yes. I'm a more effective engineer for using these tools. In this context, as a solo developer on a small project, this is especially true. Because of AI, the app is more inclusive, more architecturally sound, has a better look and feel, all accomplished in less time than if I manually designed and implemented it.

