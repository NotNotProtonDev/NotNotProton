// Downloads the free Direct3D layers into the plugin folder the Steam panel reads, so a
// prefix can be switched to one per game. Nothing is bundled: each layer comes from its own
// release when the user asks for it, and its licence travels with that download.

import Foundation
import Observation

struct GraphicsLayer: Sendable, Equatable, Identifiable {
    // Also the plugin folder and the conf name, which pair a layer with the panel's entry.
    let id: String
    let title: String
    // Written into the conf, where the panel shows it, so it is read on install.
    let summary: String
    let note: String?
    let url: URL
    // Folder inside the archive holding the DLLs that are staged into system32.
    let dllFolder: String
    // A library that has to sit in the runner instead, DXMT's winemetal.so.
    let unixLibrary: String?
    let overrides: String
    let requires: String
}

@MainActor
@Observable
final class GraphicsBackends {

    // DXVK-macOS has no d3d9, and DXMT's Metal half exists for x86_64 only, so FEX (arm64)
    // runners get neither from these two.
    nonisolated static let layers: [GraphicsLayer] = [
        GraphicsLayer(
            id: "dxvk",
            title: "DXVK",
            summary: "Direct3D 10/11 through Vulkan.",
            note: nil,
            url: URL(
                string:
                    "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
            )!,
            dllFolder: "x64",
            unixLibrary: nil,
            overrides: "d3d10core=n,b;d3d11=n,b",
            requires: "d3d11.dll"
        ),
        GraphicsLayer(
            id: "dxmt",
            title: "DXMT",
            summary: "Direct3D 10/11 through Metal.",
            note: "x86_64 runners only: it needs winemetal.so in each runner, which FEX (arm64) runners do not have.",
            url: URL(
                string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
            )!,
            dllFolder: "x86_64-windows",
            unixLibrary: "x86_64-unix/winemetal.so",
            overrides: "d3d10core=n,b;d3d11=n,b;dxgi=n,b",
            requires: "d3d11.dll"
        ),
    ]

    enum State: Equatable {
        case downloading(Double)
        case unpacking
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    private let plugins: URL
    private let runners: URL

    init(plugins: URL = GraphicsBackends.pluginsFolder, runners: URL = SupportPaths.runners) {
        self.plugins = plugins
        self.runners = runners
    }

    var isBusy: Bool {
        states.values.contains { state in
            switch state {
            case .downloading, .unpacking: true
            case .failed: false
            }
        }
    }

    nonisolated static var pluginsFolder: URL {
        SupportPaths.support.appending(path: "plugins", directoryHint: .isDirectory)
    }

    // What the conf tells the panel to stage. relative because the panel reads it from $HOME.
    nonisolated static func stagePath(_ id: String) -> String {
        "Library/Application Support/\(SupportPaths.supportDirName)/plugins/\(id)"
    }

    nonisolated static func conf(for layer: GraphicsLayer) -> String {
        """
        key = NOTPROTON_\(layer.id.uppercased())
        label = \(layer.title)
        description = \(layer.summary)
        section = dev
        stage = \(stagePath(layer.id))
        overrides = \(layer.overrides)
        requires = \(stagePath(layer.id))/\(layer.requires)

        """
    }

    nonisolated static func installed(_ layers: [GraphicsLayer] = layers, plugins: URL = pluginsFolder) -> Set<String> {
        Set(
            layers.filter { layer in
                FileManager.default.fileExists(
                    atPath: plugins.appending(path: "\(layer.id)/\(layer.requires)").path(percentEncoded: false))
            }.map(\.id))
    }

    func install(_ layer: GraphicsLayer) async -> Bool {
        states[layer.id] = .downloading(0)
        let transfer = Transfer(label: layer.id) { [weak self] id, fraction in
            Task { @MainActor in self?.report(id, fraction) }
        }
        do {
            let archive = try await transfer.start(layer.url)
            defer { try? FileManager.default.removeItem(at: archive) }

            states[layer.id] = .unpacking
            try place(layer, archive: archive)
            states[layer.id] = nil
            AppLog.note("installed \(layer.id) into \(plugins.path(percentEncoded: false))")
            return true
        } catch {
            states[layer.id] = .failed(error.localizedDescription)
            AppLog.note("\(layer.id) failed: \(error)")
            return false
        }
    }

    private func report(_ id: String, _ fraction: Double) {
        guard case .downloading = states[id] else { return }
        states[id] = .downloading(fraction)
    }

    func place(_ layer: GraphicsLayer, archive: URL) throws {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appending(path: "notproton-\(layer.id)-\(UUID().uuidString)")
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }

        let tar = try Shell.run(
            "/usr/bin/tar",
            ["-xzf", archive.path(percentEncoded: false), "-C", staging.path(percentEncoded: false)])
        guard tar.succeeded else {
            throw Failure(tar.stderr.isEmpty ? "tar exited \(tar.status)." : tar.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let folder = try tree(in: staging).first { $0.lastPathComponent == layer.dllFolder }
        guard let folder else {
            throw Failure(String(localized: "The archive does not hold a \(layer.dllFolder) folder."))
        }

        let destination = plugins.appending(path: layer.id)
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let target = destination.appending(path: file.lastPathComponent)
            try? files.removeItem(at: target)
            try files.copyItem(at: file, to: target)
        }

        if let library = layer.unixLibrary, let source = try tree(in: staging).first(where: {
            $0.path.hasSuffix("/" + library)
        }) {
            addRunnerLibrary(source)
        }

        let conf = plugins.appending(path: "\(layer.id).conf")
        if !files.fileExists(atPath: conf.path(percentEncoded: false)) {
            try Self.conf(for: layer).write(to: conf, atomically: true, encoding: .utf8)
        }
    }

    // DXMT's Metal half is loaded by the Windows side from the runner's unix folder.
    private func addRunnerLibrary(_ source: URL) {
        let files = FileManager.default
        let runnerDirs = (try? files.contentsOfDirectory(at: runners, includingPropertiesForKeys: nil)) ?? []
        for runner in runnerDirs {
            let unix = runner.appending(path: "CrossOver/lib/wine/x86_64-unix")
            guard files.fileExists(atPath: unix.path(percentEncoded: false)) else { continue }
            let target = unix.appending(path: source.lastPathComponent)
            try? files.removeItem(at: target)
            try? files.copyItem(at: source, to: target)
        }
    }

    private func tree(in root: URL) throws -> [URL] {
        let files = FileManager.default
        guard let walk = files.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walk.compactMap { $0 as? URL }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?

        init(_ message: String) { errorDescription = message }
    }
}
