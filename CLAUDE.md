# Instructions for an AI agent working in this repo

## Keep the docs in sync — every session, not just when asked

This repo has two living docs that are supposed to reflect the actual state
of the app, not a snapshot from whenever they were last touched:

- [`docs/wiggleroom-build-spec.md`](docs/wiggleroom-build-spec.md) — the
  source of truth for how the app is *supposed* to work (data model,
  architecture, visual/UX direction, platform UI, explicit out-of-scope
  items).
- [`docs/progress-notes.md`](docs/progress-notes.md) — the running,
  chronological log of what's *actually* been built, key decisions (and
  why), known gaps, and gotchas hit along the way.

**Before finishing any session that changed app behavior** (UI, model
logic, wording/copy, scheduling, bug fixes — not pure refactors with no
observable difference), do both of these, without waiting to be asked:

1. **Update `docs/wiggleroom-build-spec.md`** wherever a section it
   describes actually changed — a rewritten rule, not a patch note. If the
   spec currently describes old behavior, fix the description; don't leave
   two conflicting accounts of the same feature. Add new "Resolved" items
   to §12 for anything that was previously an open question.
2. **Append a new dated section to `docs/progress-notes.md`** (follow the
   existing format — a `## YYYY-MM-DD <short description>` heading, prose
   with file links, a summary of what changed and why, real bugs fixed
   called out explicitly, and what was/wasn't verified) and update the
   intro paragraph at the top of the file to point at it. Don't rewrite or
   delete prior sections — this file is a log, older entries stay as the
   historical record even once superseded.

Also check `README.md`'s status checklist and project-structure listing
whenever a platform, target, or top-level feature area changes — it drifts
easily and is often the first thing a human actually reads.

If a session's request comes from a screenshot, a bug report, or informal
description rather than a spec section, that's still a behavior change the
docs need to catch up to — write down what was actually wrong and what the
fix does, not just "fixed a bug."

**Before starting non-trivial work**, read the build spec and skim recent
progress-notes.md entries first, same as `README.md` already says — this
file's instruction is about the other direction (writing back afterward),
which matters just as much and is easier to skip under time pressure.

## Verifying changes in this repo

This is an Xcode multiplatform SwiftUI project (iOS/iPadOS/macOS/watchOS +
several WidgetKit extensions), built with SwiftData + CloudKit. Whether
`xcodebuild`/a simulator are available varies by environment/session — when
they are, use them (see progress-notes.md's various "Verifying..." sections
for working invocations and known gotchas with this specific project). When
they aren't, say so explicitly in both the session's own output and the
progress-notes.md entry (`swiftc -parse` syntax checks are not a substitute
for a real build, and should never be reported as if they were). Don't
claim something was verified in a simulator or on-device unless it actually
was.
