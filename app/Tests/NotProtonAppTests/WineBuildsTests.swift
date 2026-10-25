import Foundation
import Testing

@testable import NotProtonApp

@Suite("Wine build downloads")
struct WineBuildsTests {

    @Test("Every WineHQ build the patcher has hashes for is offered, and every offer is a build it knows")
    func coversSupportedBuilds() {
        let supported = Set(SupportedRunners.all.map(\.id))
        let offered = Set(WineBuilds.pinned.map(\.buildID))
        #expect(offered.isSubset(of: supported))
        #expect(offered.isSuperset(of: Set(SupportedRunners.all.filter { $0.productName == "WineHQ" }.map(\.id))))
        #expect(WineBuilds.pinned.filter { $0.base.hasSuffix("macOS_Wine_builds/releases/download") }.allSatisfy {
            $0.asset.contains($0.release)
        })
    }

    @Test("Each download is an asset of the release it names")
    func urls() {
        for build in WineBuilds.pinned {
            #expect(
                build.url.absoluteString
                    == "\(build.base)/\(build.release)/\(build.asset)"
            )
        }
    }

    @Test("The list shows the newest of each family and folds the rest away")
    func foldsOlderBuilds() {
        let newest = WineBuilds.newest(WineBuilds.pinned).map(\.buildID)
        #expect(newest == ["winehq-11.18", "winehq-staging-11.18", "wine-cx-26.3.0"])
    }

    @Test("An installed build is not offered again")
    func hidesInstalled() throws {
        let build = try #require(SupportedRunners.build(id: "winehq-11.15"))
        let install = CrossOverInstall(
            bundle: URL(filePath: "/Applications/Wine Devel.app"),
            releaseVersion: build.releaseVersion,
            support: .supported(build)
        )

        let missing = WineBuilds.missing(from: [install]).map(\.buildID)
        #expect(!missing.contains("winehq-11.15"))
        #expect(missing.count == WineBuilds.pinned.count - 1)
    }

    @Test("A version that is not pinned does not stand in for one that is")
    func ignoresOtherVersions() {
        let install = CrossOverInstall(
            bundle: URL(filePath: "/Applications/Wine 11.99.app"),
            releaseVersion: "11.99",
            support: .unsupportedBuild("11.99")
        )

        #expect(WineBuilds.installedIDs(in: [install]).isEmpty)
        #expect(WineBuilds.missing(from: [install]).count == WineBuilds.pinned.count)
    }

    @Test("Builds are unpacked where the app looks for them")
    func installsWhereItIsScanned() {
        let folder = WineBuilds.installFolder.path(percentEncoded: false)
        #expect(CrossOverSource.searchRoots.map { $0.path(percentEncoded: false) }.contains(folder))
    }

    @MainActor
    @Test("A downloaded archive is unpacked into the install folder")
    func unpacksOneApp() throws {
        let root = try fixture(apps: ["Fake.app"])
        defer { try? FileManager.default.removeItem(at: root) }

        let builds = WineBuilds(installFolder: root.appending(path: "Applications"))
        let app = try builds.unpack(root.appending(path: "wine.tar.xz"))

        #expect(app.lastPathComponent == "Fake.app")
        #expect(FileManager.default.fileExists(atPath: app.appending(path: "Contents/MacOS").path(percentEncoded: false)))
    }

    @MainActor
    @Test("An archive with more than one app is refused")
    func refusesSeveralApps() throws {
        let root = try fixture(apps: ["One.app", "Two.app"])
        defer { try? FileManager.default.removeItem(at: root) }

        let builds = WineBuilds(installFolder: root.appending(path: "Applications"))
        #expect(throws: (any Error).self) { try builds.unpack(root.appending(path: "wine.tar.xz")) }
    }

    @MainActor
    @Test("An app already in the folder is not replaced")
    func refusesToOverwrite() throws {
        let root = try fixture(apps: ["Fake.app"])
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appending(path: "Applications/Fake.app/Contents")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        let builds = WineBuilds(installFolder: root.appending(path: "Applications"))
        #expect(throws: (any Error).self) { try builds.unpack(root.appending(path: "wine.tar.xz")) }
        #expect(FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)))
    }

    @MainActor
    @Test("A bare engine tree is wrapped into the bundle the app reads")
    func wrapsBareTree() throws {
        let root = try treeFixture(version: "26.3.0")
        defer { try? FileManager.default.removeItem(at: root) }

        let builds = WineBuilds(installFolder: root.appending(path: "Applications"))
        let app = try builds.unpack(root.appending(path: "wine.tar.xz"), release: "wine-cx-26.3.0")

        #expect(app.lastPathComponent == "Wine CX 26.3.0.app")
        let tree = SupportPaths.crossOverRoot(inBundle: app)
        #expect(FileManager.default.fileExists(atPath: tree.appending(path: "lib/wine").path(percentEncoded: false)))
        #expect(CrossOverSource.releaseVersion(of: app) == "26.3.0")
        #expect(CrossOverSource.unixLoader(inBundle: app).lastPathComponent == "wine")
    }

    // An archive shaped like Barrel's: bin, lib and share at the top with no folder around them.
    private func treeFixture(version: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "np-tree-\(UUID().uuidString)")
        let source = root.appending(path: "source")
        try FileManager.default.createDirectory(
            at: source.appending(path: "lib/wine/x86_64-unix"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: source.appending(path: "bin"), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(
            to: source.appending(path: "lib/wine/x86_64-unix/wine"), atomically: true, encoding: .utf8)
        // The real one is a sentence rather than a version number.
        try "Barrel Wine, CrossOver \(version) sources (Wine version 11.0)\n"
            .write(to: source.appending(path: "version"), atomically: true, encoding: .utf8)
        let archive = root.appending(path: "wine.tar.xz")
        try Shell.run(
            "/usr/bin/tar",
            ["-cJf", archive.path(percentEncoded: false), "-C", source.path(percentEncoded: false),
             "bin", "lib", "version"])
        return root
    }

    // An archive shaped like the release's: one or more .app folders at the top.
    private func fixture(apps: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "np-wine-\(UUID().uuidString)")
        let source = root.appending(path: "source")
        for app in apps {
            try FileManager.default.createDirectory(
                at: source.appending(path: "\(app)/Contents/MacOS"), withIntermediateDirectories: true)
        }
        let archive = root.appending(path: "wine.tar.xz")
        try Shell.run(
            "/usr/bin/tar", ["-cJf", archive.path(percentEncoded: false), "-C", source.path(percentEncoded: false)] + apps
        )
        return root
    }
}
