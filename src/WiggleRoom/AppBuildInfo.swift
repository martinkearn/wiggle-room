//
//  AppBuildInfo.swift
//  WiggleRoom
//

import Foundation

/// "Are these two devices actually running the same code?" signal for the
/// About screen — added 2026-09-18 after real confusion in the field while
/// debugging a sync issue, not knowing whether a device was genuinely
/// running the latest build. Widened 2026-09-24 to carry the commit's
/// subject, date, branch and originating CI run, so a TestFlight tester
/// can see what changed in the build they've just been handed rather than
/// only an opaque hash.
///
/// The commit identity is deliberately **not** a date/time-based build
/// timestamp: two devices built minutes apart from the exact same commit
/// would then show different "versions" despite running identical code,
/// which answers the wrong question — what matters is whether the *code*
/// matches, not when it happened to get compiled.
///
/// A build script (`Write Build Info Resource`, the `WiggleRoom` target's
/// last build phase) writes a plain `build-info.txt` resource into the
/// built app. **Not** written into Info.plist and **not** a
/// compiled/generated Swift source: the former conflicts with Xcode's own
/// Info.plist generation step under User Script Sandboxing (two build
/// steps can't write the same file — "invalid task ... mutable output but
/// no other virtual output node"), and the latter wasn't picked up as a
/// compile input by this project's file-system-synchronized source groups.
/// A plain bundled text resource, read at runtime, sidesteps both. Only in
/// the `WiggleRoom` target (not `WiggleRoomShared`) since only this
/// target's build has the generating script phase.
///
/// `version` and `buildNumber` come from the bundle rather than this
/// resource: `CURRENT_PROJECT_VERSION` is set per run by the TestFlight
/// workflows, so `CFBundleVersion` is the number a tester sees against the
/// build in TestFlight itself and is worth showing verbatim.
enum AppBuildInfo {
    /// "a1b2c3d" / "a1b2c3d-dirty" / "Unknown" if the resource is missing
    /// (e.g. a build system that skips custom script phases).
    static var gitCommitDescription: String {
        value(for: "commit") ?? "Unknown"
    }

    /// Subject line of the commit this build was made from — the "what
    /// changed" a tester actually reads. `nil` for builds whose resource
    /// predates this field or couldn't be read.
    static var commitSubject: String? {
        value(for: "subject")
    }

    /// Commit date, parsed from the strict ISO 8601 the build script
    /// writes. `nil` when absent or unparseable.
    static var commitDate: Date? {
        guard let raw = value(for: "date") else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// Branch the build came from — `GITHUB_REF_NAME` in CI, since the
    /// runner's checkout is detached and would otherwise report "HEAD".
    static var branch: String? {
        value(for: "branch")
    }

    /// GitHub Actions run number, present only for builds produced by CI.
    /// Its absence is what marks a build as locally made.
    static var runNumber: String? {
        value(for: "runNumber")
    }

    /// Link to the GitHub Actions run that produced this build, for the
    /// rare case of needing the full log.
    static var runURL: URL? {
        guard let raw = value(for: "runURL") else { return nil }
        return URL(string: raw)
    }

    /// Marketing version, e.g. "1.0".
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    /// The build number TestFlight itself shows against this build.
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    /// Whether this build came off the CI pipeline rather than someone's
    /// Mac — drives whether the About screen offers the run link.
    static var isContinuousIntegrationBuild: Bool {
        runNumber != nil
    }

    /// Parsed once: the resource is written at build time and cannot
    /// change while the app runs.
    private static let fields: [String: String] = {
        guard let url = Bundle.main.url(forResource: "build-info", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }

        var parsed: [String: String] = [:]
        for line in text.split(separator: "\n") {
            // Split on the first "=" only: a commit subject may itself
            // contain one, and the key never does.
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator])
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                parsed[key] = value
            }
        }
        return parsed
    }()

    private static func value(for key: String) -> String? {
        fields[key]
    }
}
