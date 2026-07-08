import Foundation

enum BinaryResolverError: LocalizedError {
    case notFound
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "image-forge binary not found. Reinstall ImageForgeGUI.app (image-forge ships bundled), set $IMAGE_FORGE_BIN, install it at ~/bin/image-forge, or put it on your PATH."
        }
    }
}

/// Locates the `image-forge` CLI binary that the GUI drives. The **bundled**
/// copy in the .app's Resources is the trust anchor — it ships Developer-ID
/// signed + notarized (`make build-app` embeds it), so it resolves first and
/// can't be swapped without invalidating the signature. The remaining fallbacks
/// let a dev build (or an un-bundled install) find a locally-built binary.
///
/// Resolution order (mirrors the template's CLIRunner approach):
///   bundled → `$IMAGE_FORGE_BIN` (DEBUG only) → `~/bin/image-forge` → each dir on `$PATH`.
enum BinaryResolver {
    /// Resolve using the real filesystem, or throw `.notFound`.
    static func resolve() throws -> URL {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("image-forge").path
        var env = ProcessInfo.processInfo.environment
        #if !DEBUG
        // Trust boundary: a release .app always ships the signed, bundled binary
        // (which resolves first), so drop $IMAGE_FORGE_BIN in release rather than
        // let an env var redirect a shipped app to an unsigned binary. Honored in
        // DEBUG so dev builds can run against a locally-built CLI.
        env.removeValue(forKey: "IMAGE_FORGE_BIN")
        #endif
        guard let path = resolvePath(
            env: env,
            homeDir: NSHomeDirectory(),
            bundled: bundled,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        ) else {
            throw BinaryResolverError.notFound
        }
        return URL(fileURLWithPath: path)
    }

    /// Pure resolution logic (injectable for tests). Returns the first candidate
    /// that `isExecutable` accepts, in the fixed order documented above; `nil`
    /// when nothing is executable.
    static func resolvePath(
        env: [String: String],
        homeDir: String,
        bundled: String?,
        isExecutable: (String) -> Bool
    ) -> String? {
        var order: [String] = []
        if let bundled, !bundled.isEmpty { order.append(bundled) }
        if let p = env["IMAGE_FORGE_BIN"], !p.isEmpty { order.append(p) }
        order.append(homeDir + "/bin/image-forge")
        if let hit = order.first(where: isExecutable) { return hit }

        // PATH search: first `<dir>/image-forge` that is executable.
        if let path = env["PATH"] {
            for dir in path.split(separator: ":", omittingEmptySubsequences: true) {
                let candidate = String(dir) + "/image-forge"
                if isExecutable(candidate) { return candidate }
            }
        }
        return nil
    }
}
