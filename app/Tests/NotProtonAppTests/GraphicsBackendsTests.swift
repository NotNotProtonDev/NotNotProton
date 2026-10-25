import Foundation
import Testing

@testable import NotProtonApp

@Suite("Graphics backends")
struct GraphicsBackendsTests {

    private static let dxvk = try! #require(GraphicsBackends.layers.first { $0.id == "dxvk" })

    @Test("The conf tells the panel where the layer is staged")
    func confText() {
        let conf = GraphicsBackends.conf(for: Self.dxvk)

        // The panel refuses a key that is not NOTPROTON_ plus capitals, and skips the file.
        #expect(conf.contains("key = NOTPROTON_DXVK"))
        #expect(conf.contains("label = DXVK"))
        #expect(conf.contains("section = dev"))
        #expect(conf.contains("stage = Library/Application Support/notproton/plugins/dxvk"))
        #expect(conf.contains("overrides = d3d10core=n,b;d3d11=n,b"))
        #expect(conf.contains("requires = Library/Application Support/notproton/plugins/dxvk/d3d11.dll"))
    }

    @Test("Every key is one the panel accepts")
    func keysAreAccepted() {
        for layer in GraphicsBackends.layers {
            let key = GraphicsBackends.conf(for: layer)
                .split(separator: "\n")
                .first { $0.hasPrefix("key = ") }?
                .dropFirst("key = ".count) ?? ""
            #expect(key.hasPrefix("NOTPROTON_"))
            #expect(key.dropFirst("NOTPROTON_".count).allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" })
        }
    }

    @MainActor
    @Test("An archive is unpacked into the plugin folder with its conf")
    func stagesLayer() throws {
        let root = try fixture(app: "launch")
        defer { try? FileManager.default.removeItem(at: root) }

        let backends = GraphicsBackends(plugins: root.appending(path: "plugins"), runners: root.appending(path: "runners"))
        try backends.place(Self.dxvk, archive: root.appending(path: "layer.tgz"))

        let plugins = root.appending(path: "plugins")
        #expect(FileManager.default.fileExists(atPath: plugins.appending(path: "dxvk/d3d11.dll").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: plugins.appending(path: "dxvk.conf").path(percentEncoded: false)))
        #expect(GraphicsBackends.installed(plugins: plugins) == ["dxvk"])
    }

    @MainActor
    @Test("A conf that is already there is left alone")
    func keepsEditedConf() throws {
        let root = try fixture(app: "launch")
        defer { try? FileManager.default.removeItem(at: root) }
        let plugins = root.appending(path: "plugins")
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        let conf = plugins.appending(path: "dxvk.conf")
        try "key = NOTPROTON_DXVK\nlabel = Mine\n".write(to: conf, atomically: true, encoding: .utf8)

        let backends = GraphicsBackends(plugins: plugins, runners: root.appending(path: "runners"))
        try backends.place(Self.dxvk, archive: root.appending(path: "layer.tgz"))

        #expect(try String(contentsOf: conf, encoding: .utf8) == "key = NOTPROTON_DXVK\nlabel = Mine\n")
    }

    @MainActor
    @Test("DXMT's library goes into each x86_64 runner that has one")
    func copiesRunnerLibrary() throws {
        let root = try fixture(app: "launch")
        defer { try? FileManager.default.removeItem(at: root) }
        let runners = root.appending(path: "runners")
        let unix = runners.appending(path: "crossover-11.18/CrossOver/lib/wine/x86_64-unix")
        let arm = runners.appending(path: "crossover-11.18/CrossOver/lib/wine/aarch64-unix")
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: arm, withIntermediateDirectories: true)

        let dxmt = try #require(GraphicsBackends.layers.first { $0.id == "dxmt" })
        let backends = GraphicsBackends(plugins: root.appending(path: "plugins"), runners: runners)
        try backends.place(dxmt, archive: root.appending(path: "layer.tgz"))

        #expect(FileManager.default.fileExists(atPath: unix.appending(path: "winemetal.so").path(percentEncoded: false)))
        #expect(
            !FileManager.default.fileExists(
                atPath: arm.appending(path: "winemetal.so").path(percentEncoded: false)))
    }

    @Test("An archive without the expected folder is refused")
    @MainActor
    func refusesWrongArchive() throws {
        let root = try fixture(app: "launch")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = FileManager.default.temporaryDirectory.appending(path: "np-empty-\(UUID().uuidString).tgz")
        defer { try? FileManager.default.removeItem(at: archive) }
        let archiveAt = archive.path(percentEncoded: false)
        let rootAt = root.path(percentEncoded: false)
        try Shell.run("/usr/bin/tar", ["-czf", archiveAt, "-C", rootAt, "launch"])

        let backends = GraphicsBackends(plugins: root.appending(path: "plugins"), runners: root.appending(path: "runners"))
        #expect(throws: (any Error).self) { try backends.place(Self.dxvk, archive: archive) }
    }

    // An archive shaped like the release's: <anything>/x64/*.dll and <anything>/x86_64-unix/winemetal.so.
    private func fixture(app: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "np-layer-\(UUID().uuidString)")
        let source = root.appending(path: "source/payload")
        try FileManager.default.createDirectory(at: source.appending(path: "x64"), withIntermediateDirectories: true)
        try Data("dll".utf8).write(to: source.appending(path: "x64/d3d11.dll"))
        try FileManager.default.createDirectory(
            at: source.appending(path: "x86_64-windows"), withIntermediateDirectories: true)
        try Data("dll".utf8).write(to: source.appending(path: "x86_64-windows/d3d11.dll"))
        try FileManager.default.createDirectory(
            at: source.appending(path: "x86_64-unix"), withIntermediateDirectories: true)
        try Data("so".utf8).write(to: source.appending(path: "x86_64-unix/winemetal.so"))

        let archive = root.appending(path: "layer.tgz").path(percentEncoded: false)
        let sourceAt = root.appending(path: "source").path(percentEncoded: false)
        try Shell.run("/usr/bin/tar", ["-czf", archive, "-C", sourceAt, "payload"])
        return root
    }
}
