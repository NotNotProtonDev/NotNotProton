// Drives a download task directly, because the URLSession convenience downloads report no
// progress and hand back a file that cannot be kept once the call returns.

import Foundation

enum TransferError: LocalizedError {
    case answered(Int)
    case noFile

    var errorDescription: String? {
        switch self {
        case .answered(let code): "The server answered \(code)."
        case .noFile: "The download finished without a file."
        }
    }
}

final class Transfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let label: String
    private let report: @Sendable (String, Double) -> Void
    private let lock = NSLock()
    private var kept: URL?
    private var failure: Error?
    private var finish: ((Result<URL, Error>) -> Void)?

    init(label: String, report: @escaping @Sendable (String, Double) -> Void = { _, _ in }) {
        self.label = label
        self.report = report
    }

    func start(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { finish = { continuation.resume(with: $0) } }
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        report(label, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            lock.withLock { failure = TransferError.answered(http.statusCode) }
            return
        }
        let kept = FileManager.default.temporaryDirectory.appending(path: "notproton-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            lock.withLock { self.kept = kept }
        } catch {
            lock.withLock { failure = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (finish, outcome): (((Result<URL, Error>) -> Void)?, Result<URL, Error>) = lock.withLock {
            if let error { return (self.finish, .failure(error)) }
            if let kept { return (self.finish, .success(kept)) }
            return (self.finish, .failure(failure ?? TransferError.noFile))
        }
        finish?(outcome)
    }
}
