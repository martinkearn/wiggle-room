//
//  AboutView.swift
//  WiggleRoom
//

import SwiftUI

/// Settings page describing exactly which build is running: marketing
/// version, the build number TestFlight shows, and the commit that
/// produced it. Added 2026-09-24 to give the build details one deliberate
/// home — previously a bare "Build <hash>" line sat at the bottom of the
/// iOS settings list and again under macOS General, which buried it and
/// duplicated it.
///
/// Worth more than a version string because this app ships to TestFlight
/// off every push to `main`: a tester looking at an unexpected behaviour
/// needs to know which change they're actually holding. See
/// `AppBuildInfo`'s doc comment for where each field comes from and why a
/// git commit rather than a build timestamp.
struct AboutView: View {
    private var commitDateText: String? {
        guard let date = AppBuildInfo.commitDate else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            Text("About").font(WiggleRoomFont.headline(22, weight: 650))

            VStack(alignment: .leading, spacing: 6) {
                Text("Wiggle Room \(AppBuildInfo.version)")
                    .font(WiggleRoomFont.headline(17, weight: 650))
                Text("Build \(AppBuildInfo.buildNumber)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("This Build").font(WiggleRoomFont.headline(17, weight: 650))
                if let subject = AppBuildInfo.commitSubject {
                    Text(subject)
                }
                Text(sourceSummary)
                    .font(.wiggleText(.caption))
                    .foregroundStyle(.secondary)
                if let url = AppBuildInfo.runURL {
                    Link("View the build on GitHub", destination: url)
                        .font(.wiggleText(.caption))
                }
            }

            Spacer()
        }
        #else
        List {
            Section {
                LabeledContent("Version", value: AppBuildInfo.version)
                LabeledContent("Build", value: AppBuildInfo.buildNumber)
            } header: {
                Text("Wiggle Room")
                    .font(WiggleRoomFont.headline(15, weight: 650))
            }

            Section {
                if let subject = AppBuildInfo.commitSubject {
                    Text(subject)
                }
                LabeledContent("Commit", value: AppBuildInfo.gitCommitDescription)
                if let branch = AppBuildInfo.branch {
                    LabeledContent("Branch", value: branch)
                }
                if let commitDateText {
                    LabeledContent("Committed", value: commitDateText)
                }
                if let runNumber = AppBuildInfo.runNumber {
                    LabeledContent("Pipeline Run", value: "#\(runNumber)")
                }
                if let url = AppBuildInfo.runURL {
                    Link("View the build on GitHub", destination: url)
                }
            } header: {
                Text("This Build")
                    .font(WiggleRoomFont.headline(15, weight: 650))
            } footer: {
                // Confirms two devices are running the exact same code —
                // see `AppBuildInfo`'s own doc comment for why this is a
                // git commit rather than a build date or version number.
                Text(AppBuildInfo.isContinuousIntegrationBuild
                     ? "Built automatically from this commit and sent to TestFlight."
                     : "Built locally, so it may not match any TestFlight build.")
            }
        }
        .navigationTitle("About")
        .inlineNavigationBarIfAvailable()
        #endif
    }

    /// One compact line for macOS, where the sidebar pane has less room
    /// than iOS's grouped list for a row apiece.
    private var sourceSummary: String {
        var parts = [AppBuildInfo.gitCommitDescription]
        if let branch = AppBuildInfo.branch {
            parts.append("on \(branch)")
        }
        if let commitDateText {
            parts.append("· \(commitDateText)")
        }
        if let runNumber = AppBuildInfo.runNumber {
            parts.append("· run #\(runNumber)")
        }
        return parts.joined(separator: " ")
    }
}

#Preview {
    NavigationStack { AboutView() }
}
