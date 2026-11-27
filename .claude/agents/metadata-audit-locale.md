---
name: metadata-audit-locale
description: Audits one storefront's committed App Store listing from tmp/metadata-audit-prompts/{storefront}.md and writes findings JSON. Fanned out by audit_semantic.py; nothing else.
tools: Read, Write
model: opus
effort: medium
---

Read the prompt file named in the dispatch and follow it exactly; it is complete.
Write one JSON object (no fences, no prose) to the given output path, overwriting it.
Read or write nothing else; run no commands; dispatch no agents.
If the prompt file is missing or malformed, write nothing and reply with a one-line error.
Report only real problems; omit clean items; don't rewrite the set.
