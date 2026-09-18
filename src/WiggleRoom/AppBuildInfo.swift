//
//  AppBuildInfo.swift
//  WiggleRoom
//

import Foundation

/// "Are these two devices actually running the same code?" signal for
/// Settings — added 2026-09-18 after real confusion in the field while
/// debugging a sync issue, not knowing whether a device was genuinely
/// running the latest build.
///
/// Deliberately **not** a date/time-based build timestamp: two devices
/// built minutes apart from the exact same commit would then show
/// different "versions" despite running identical code, which answers the
/// wrong question — what actually matters is whether the *code* matches,
/// not when it happened to get compiled. Also deliberately not
/// `CFBundleShortVersionString`/`CFBundleVersion` — this project doesn't
/// bump either automatically, so they'd stay flatly "1.0 (1)" forever.
///
/// Instead, a build script (`Write Git Commit Resource`, the `WiggleRoom`
/// target's last build phase) writes a plain `git-commit.txt` resource
/// into the built app containing the current git commit's short hash —
/// plus a `-dirty` suffix if the working tree has uncommitted changes.
/// **Not** written into Info.plist and **not** a compiled/generated Swift
/// source: the former conflicts with Xcode's own Info.plist generation
/// step under User Script Sandboxing (two build steps can't write the
/// same file — "invalid task ... mutable output but no other virtual
/// output node"), and the latter wasn't picked up as a compile input by
/// this project's file-system-synchronized source groups. A plain bundled
/// text resource, read at runtime, sidesteps both. Two builds from the
/// same commit show the identical value regardless of machine or build
/// time; any real code difference changes it. Only in the `WiggleRoom`
/// target (not `WiggleRoomShared`) since only this target's build has the
/// generating script phase.
enum AppBuildInfo {
    /// "a1b2c3d" / "a1b2c3d-dirty" / "Unknown" if the resource is missing
    /// (e.g. a build system that skips custom script phases).
    static var gitCommitDescription: String {
        guard let url = Bundle.main.url(forResource: "git-commit", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "Unknown" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}
