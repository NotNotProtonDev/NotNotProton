// Downloads the WineHQ builds pinned in SupportedRunners, so a release does not ask the
// user to find the right asset on Gcenx's releases page themselves.

import Foundation
import Observation

struct WineBuildDownload: Sendable, Equatable, Identifiable {
    // Matches a build id in SupportedRunners.
    let buildID: String
    // The release tag and the asset under it.
    let release: String
    let asset: String

    // Where the release lives. Gcenx publishes the WineHQ builds, Barrel the FOSS CrossOver one.
    var base = "https://github.com/Gcenx/macOS_Wine_builds/releases/download"

    var id: String { buildID }

    var url: URL {
        URL(string: "\(base)/\(release)/\(asset)")!
    }

    var title: String {
        SupportedRunners.build(id: buildID)?.tools.first?.display ?? asset
    }
}

@MainActor
@Observable
final class WineBuilds {

    // The patcher only knows the ntdll offsets for the builds pinned in SupportedRunners,
    // so those are the only ones offered here.
    nonisolated static let pinned: [WineBuildDownload] = [
        WineBuildDownload(buildID: "winehq-11.15", release: "11.15", asset: "wine-devel-11.15-osx64.tar.xz"),
        WineBuildDownload(
            buildID: "winehq-staging-11.15", release: "11.15", asset: "wine-staging-11.15-osx64.tar.xz"),
        WineBuildDownload(buildID: "winehq-11.18", release: "11.18", asset: "wine-devel-11.18-osx64.tar.xz"),
        WineBuildDownload(
            buildID: "winehq-staging-11.18", release: "11.18", asset: "wine-staging-11.18-osx64.tar.xz"),
        WineBuildDownload(buildID: "winehq-11.17", release: "11.17", asset: "wine-devel-11.17-osx64.tar.xz"),
        WineBuildDownload(
            buildID: "winehq-staging-11.17", release: "11.17", asset: "wine-staging-11.17-osx64.tar.xz"),
        WineBuildDownload(buildID: "winehq-11.16", release: "11.16", asset: "wine-devel-11.16-osx64.tar.xz"),
        WineBuildDownload(
            buildID: "winehq-staging-11.16", release: "11.16", asset: "wine-staging-11.16-osx64.tar.xz"),
        WineBuildDownload(
            buildID: "winehq-staging-11.9", release: "11.9", asset: "wine-staging-11.9-osx64.tar.xz"),
        // CrossOver 26.3 compiled from CodeWeavers' open source tree, so the engine without the
        // licence. Ships as a bare bin/lib/share tree rather than an app.
        WineBuildDownload(
            buildID: "wine-cx-26.3.0", release: "wine-cx-26.3.0", asset: "barrel-wine-26.3.0.tar.xz",
            base: "https://github.com/MrTuNNe/Barrel/releases/download"),
    ]

    enum State: Equatable {
        case downloading(Double)
        case unpacking
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    private let folder: URL

    init(installFolder: URL = WineBuilds.installFolder) { folder = installFolder }

    var isBusy: Bool {
        states.values.contains { state in
            switch state {
            case .downloading, .unpacking: true
            case .failed: false
            }
        }
    }

    // CrossOverSource scans this folder, so an unpacked build needs no further registration.
    nonisolated static var installFolder: URL {
        SupportPaths.home.appending(path: "Applications", directoryHint: .isDirectory)
    }

    nonisolated static func installedIDs(in installs: [CrossOverInstall]) -> Set<String> {
        Set(
            installs.compactMap { install in
                guard case .supported(let build) = install.support else { return nil }
                return build.id
            })
    }

    nonisolated static func missing(from installs: [CrossOverInstall]) -> [WineBuildDownload] {
        let installed = installedIDs(in: installs)
        return pinned.filter { !installed.contains($0.buildID) }
    }

    // One entry per family, so the list shows the newest of each rather than every version.
    nonisolated static func newest(_ builds: [WineBuildDownload]) -> [WineBuildDownload] {
        var best: [String: WineBuildDownload] = [:]
        for build in builds {
            guard let incumbent = best[family(of: build)] else {
                best[family(of: build)] = build
                continue
            }
            if isNewer(build.release, than: incumbent.release) { best[family(of: build)] = build }
        }
        return builds.filter { best[family(of: $0)]?.buildID == $0.buildID }
    }

    nonisolated static func family(of build: WineBuildDownload) -> String {
        if build.buildID.hasPrefix("winehq-staging-") { return "winehq-staging" }
        if build.buildID.hasPrefix("winehq-") { return "winehq" }
        return build.buildID
    }

    // 11.18 is newer than 11.9, which comparing the strings would get wrong.
    private nonisolated static func isNewer(_ version: String, than other: String) -> Bool {
        let left = version.split(separator: ".").map { Int($0) ?? 0 }
        let right = other.split(separator: ".").map { Int($0) ?? 0 }
        for (a, b) in zip(left, right) where a != b { return a > b }
        return left.count > right.count
    }

    func download(_ build: WineBuildDownload) async -> URL? {
        states[build.id] = .downloading(0)
        let transfer = Transfer(label: build.id) { [weak self] id, fraction in
            Task { @MainActor in self?.report(id, fraction) }
        }
        do {
            let archive = try await transfer.start(build.url)
            defer { try? FileManager.default.removeItem(at: archive) }

            states[build.id] = .unpacking
            let app = try unpack(archive, release: build.release)
            states[build.id] = nil
            AppLog.note("unpacked \(build.asset) into \(app.path(percentEncoded: false))")
            return app
        } catch {
            states[build.id] = .failed(error.localizedDescription)
            AppLog.note("\(build.asset) failed: \(error)")
            return nil
        }
    }

    private func report(_ build: String, _ fraction: Double) {
        guard case .downloading = states[build] else { return }
        states[build] = .downloading(fraction)
    }

    func unpack(_ archive: URL, release: String? = nil) throws -> URL {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appending(path: "notproton-wine-\(UUID().uuidString)")
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }

        let tar = try Shell.run(
            "/usr/bin/tar",
            ["-xJf", archive.path(percentEncoded: false), "-C", staging.path(percentEncoded: false)])
        guard tar.succeeded else {
            throw Failure(
                tar.stderr.isEmpty ? "tar exited \(tar.status)." : tar.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let app = try appOrWrapped(in: staging, release: release)

        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: app.lastPathComponent)
        guard !files.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw Failure(
                String(localized: "\(app.lastPathComponent) is already in \(folder.path(percentEncoded: false)).")
            )
        }
        try files.moveItem(at: app, to: destination)
        return destination
    }

    // Gcenx ships a Wine app. Barrel ships the bare engine tree, which gets the same bundle
    // layout CrossOver uses so the rest of the app reads it the usual way.
    private func appOrWrapped(in staging: URL, release: String?) throws -> URL {
        let files = FileManager.default
        let entries = try files.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        let apps = entries.filter { $0.pathExtension == "app" }
        if apps.count == 1, let app = apps.first { return app }
        guard apps.isEmpty else {
            throw Failure(String(localized: "The archive does not hold one Wine app."))
        }

        func holdsWine(_ url: URL) -> Bool {
            files.fileExists(atPath: url.appending(path: "lib/wine").path(percentEncoded: false))
        }
        // Barrel's archive puts bin, lib and share straight at the top with no folder around them.
        let tree: URL
        if let folder = entries.first(where: holdsWine) {
            tree = folder
        } else if holdsWine(staging) {
            tree = staging
        } else {
            throw Failure(String(localized: "The archive does not hold one Wine app."))
        }

        // Barrel's version file is prose, so the release tag is the reliable name.
        var version = release?.replacingOccurrences(of: "wine-cx-", with: "")
            ?? (try? String(contentsOf: tree.appending(path: "version"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "unknown"
        if version.isEmpty || version.contains(" ") { version = "unknown" }
        let name = "Wine CX \(version)"
        let app = tree.deletingLastPathComponent().appending(path: "\(name).app")
        let contents = app.appending(path: "Contents")
        let root = contents.appending(path: "SharedSupport/CrossOver")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        for entry in try files.contentsOfDirectory(at: tree, includingPropertiesForKeys: nil) {
            try files.moveItem(at: entry, to: root.appending(path: entry.lastPathComponent))
        }
        try files.removeItem(at: tree)
        try plist(name: name, version: version).write(
            to: contents.appending(path: "Info.plist"), atomically: true, encoding: .utf8)
        return app
    }

    private func plist(name: String, version: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>CFBundleName</key><string>\(name)</string>
        \t<key>CFBundlePackageType</key><string>APPL</string>
        \t<key>CFBundleShortVersionString</key><string>\(version)</string>
        </dict>
        </plist>
        """
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?

        init(_ message: String) { errorDescription = message }
    }

}
