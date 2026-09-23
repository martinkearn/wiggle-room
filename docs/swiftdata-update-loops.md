# SwiftData update loops in nested views

An engineering note, not part of the product specification. It records a
class of bug this app hit repeatedly, why it was hard to find, and how to
recognise it again. The rule it produced lives in the build specification
under **Persistence and sync**; the reasoning and the evidence live here.

## Symptom

Opening a pushed or presented editor screen pegged the main thread and the
app died a few seconds later. Crash reports showed `EXC_CRASH (SIGKILL)`
with `0x8BADF00D` — a watchdog kill, either `scene-update` or
`process-exit`, never a normal exception.

The distinguishing signature, visible in both a CPU-resource report and a
`sample` of the running process:

- The whole stack sits inside **one** SwiftUI graph update —
  `AG::Graph::UpdateStack::update()` → `DynamicBody.updateValue()` →
  `ViewBodyAccessor.updateBody(of:changed:)` → the view's `body` — that
  never returns to idle.
- Memory climbs steadily (observed: 32 MB → 814 MB in under two minutes,
  about 4 MB/s), because AttributeGraph allocates on every pass.
- `Self._printChanges()` reports `@self changed` for the child on every
  pass, and the same count for the parent — the two rebuild in lockstep.

A hang whose stack is a *single* non-returning graph update is this bug. A
hang blocked in `-[NSOperation waitUntilFinished]` or a semaphore is a
different problem (a real deadlock) and should not be diagnosed with this
note.

## Mechanism

Two things sustain the loop:

1. A **presenting view that holds a live `@Query`**, so it rebuilds whenever
   the store changes.
2. A **presented view whose `body` touches SwiftData**, built inside the
   presenter's `body` — a `NavigationLink(destination:)`, a `.sheet`
   content closure, or a plain child view.

The cycle: the child's fetch runs on the shared main `ModelContext`; that
notifies SwiftData's change observers; the parent's `@Query` republishes and
its `body` re-runs; that constructs a brand-new child value (a fresh query,
and fresh `State(initialValue:)` storage, so it can never compare equal to
its predecessor); the child fetches again.

Nothing external drives it. It runs at display-refresh rate with no user
input until the watchdog fires.

## Why it resisted several fixes

**It is not limited to queries over the same model type.** The first fix
removed only the child's duplicate `ConnectedSource` query — the one
matching the parent's — and left a query over the request log, on the
reasoning that no ancestor queried that type. The hang survived. The parent
only has to be *invalidated*, and a `@Query` republishes on store-change
notifications broadly rather than strictly per type.

**It does not reproduce against a quiet store.** The loop needs the
presenting view to keep rebuilding, which requires the store to keep
changing. On a real device that happens continuously — Starling request
logging inserts rows, CloudKit imports arrive. A simulator with seeded data
that then sits still will not reproduce it, which is why several rounds of
local debugging came back clean and the bug was wrongly attributed to a
CloudKit production-schema gap.

**It is easy to blame the wrong platform difference.** macOS was unaffected
simply because it never runs this code path: `ConnectedSourcesView.macBody`
swaps list-to-detail through `SourceEditorCard` with no `NavigationLink`.
The two platforms were not the same code behaving differently.

## The rule

A screen pushed or presented from a `@Query`-backed view **should not
observe SwiftData from its `body` at all** — no live query, no relationship
traversal, no model property read during `body`.

Seed local `@State` in `init` or on appear, and read the model only in the
action that saves. Validation that needs current data (a duplicate-name
check) belongs in that save action, against a one-shot fetch, where
correctness actually matters and a stale snapshot cannot cause harm.

Live `@Query` remains correct and preferred for a view that is not itself
rebuilt by another view's query — list screens, the macOS inline editors.

## How to reproduce one

Against a **changing** store, not merely a populated one. A temporary debug
hook that, on a timer, inserts a record through a short-lived
`ModelContext`, mutates a model on the main context, and posts
`.NSPersistentStoreRemoteChange` approximates a device under CloudKit sync
closely enough to expose the loop.

Then measure rather than infer:

- `ps -o %cpu=,rss=` for the signature (pegged CPU, steadily climbing RSS).
  Note this reports a decaying average, not an instantaneous value.
- `sample <pid> 4` for a symbolicated stack, and to confirm whether the
  suspect view appears at all. A view that never appears in a multi-second
  sample is not re-rendering.
- `Self._printChanges()` in the suspect bodies to see which view invalidates
  and why.
- Bisect with environment-variable toggles compiled into one build, rather
  than rebuilding per hypothesis.

## History

- **2026-09-22** — `AddSourceView` gained a second live `@Query` over
  `ConnectedSource`, duplicating `ConnectedSourcesView`'s. Opening a
  connected source on iOS began hanging. Diagnosed and partly fixed;
  `AddTrackerView` and the macOS `SourceEditorCard`/`NewSourceCard` carried
  the same latent pattern and were changed to snapshots at the same time.
- **2026-09-23** — The hang recurred on TestFlight build 2027.1.1. The
  remaining live query over `StarlingRequestLogEntry` was enough to sustain
  it. The iOS connected-source editor was reduced to a name field, a token
  field, and save, so its `body` observes nothing from SwiftData. Confirmed
  fixed on build 2028.1.1.
- **2026-09-23** — The request counter was restored to that screen as a
  `.task` snapshot rather than a live `@Query`: read once on appear, so the
  figure doesn't tick while the screen is open. Verified inert afterwards —
  zero `AddSourceView` frames in a five-second sample under a store being
  written to twice a second. This is the pattern for putting store-derived
  detail back on such a screen.
- **2026-09-23** — The Connected/Not Connected indicator was restored the
  same way, as a `let` captured in `init`. Cheaper still than the counter:
  no fetch at all, and nothing can change it while the screen is open, since
  saving a token dismisses. Re-verified inert (zero `AddSourceView` frames in
  4,130 samples).
