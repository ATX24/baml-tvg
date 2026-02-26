#if os(macOS)
import Foundation

/// Downloads libbaml_cffi.dylib from GitHub releases on macOS.
/// Mirrors the Go client's findOrDownloadLibrary() in lib_common.go.
internal enum MacOSDownloader {
    // This is updated by CI on each release
    static let version = "0.219.0"

    private static let githubRepo = "boundaryml/baml"
    private static let cacheSubdir = "baml/libs"

    /// Find the library locally or download it from GitHub releases.
    /// Returns the absolute path to the dylib.
    static func findOrDownloadLibrary() throws -> String {
        // 1. Check BAML_LIBRARY_PATH env var
        if let envPath = ProcessInfo.processInfo.environment["BAML_LIBRARY_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }

        // 2. Check cache directory
        let cacheDir = getCacheDir()
        let filename = "libbaml_cffi-\(targetTriple()).dylib"
        let cachedPath = (cacheDir as NSString).appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: cachedPath) {
            return cachedPath
        }

        // 3. Check if downloads are disabled
        if ProcessInfo.processInfo.environment["BAML_LIBRARY_DISABLE_DOWNLOAD"]?
            .lowercased() == "true" {
            throw BamlError.libraryNotFound(
                "BAML library not found at \(cachedPath) and download is disabled. "
                + "Set BAML_LIBRARY_PATH to the path of libbaml_cffi.dylib or enable downloads."
            )
        }

        // 4. Download from GitHub releases
        let url = "https://github.com/\(githubRepo)/releases/download/\(version)/\(filename)"
        try download(from: url, to: cachedPath)

        return cachedPath
    }

    private static func targetTriple() -> String {
        #if arch(arm64)
        return "aarch64-apple-darwin"
        #elseif arch(x86_64)
        return "x86_64-apple-darwin"
        #else
        fatalError("BamlSwift: Unsupported macOS architecture")
        #endif
    }

    private static func getCacheDir() -> String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("\(cacheSubdir)/\(version)").path
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return dir
    }

    private static func download(from urlString: String, to destPath: String) throws {
        guard let url = URL(string: urlString) else {
            throw BamlError.downloadFailed("Invalid download URL: \(urlString)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var downloadError: Error?

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            defer { semaphore.signal() }

            if let error = error {
                downloadError = BamlError.downloadFailed(
                    "Failed to download from \(urlString): \(error.localizedDescription)"
                )
                return
            }

            guard let tempURL = tempURL,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                downloadError = BamlError.downloadFailed(
                    "HTTP \(code) downloading from \(urlString)"
                )
                return
            }

            do {
                // Remove existing file if present
                if FileManager.default.fileExists(atPath: destPath) {
                    try FileManager.default.removeItem(atPath: destPath)
                }
                try FileManager.default.moveItem(atPath: tempURL.path, toPath: destPath)
                // Make executable
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: destPath
                )
            } catch {
                downloadError = BamlError.downloadFailed(
                    "Failed to save library: \(error.localizedDescription)"
                )
            }
        }
        task.resume()
        semaphore.wait()

        if let error = downloadError {
            throw error
        }
    }
}
#endif
