import Foundation

/// Generation metadata recovered from a PNG's text chunks. image-forge (ADR-0005)
/// embeds two chunks into every generated image: an `image-forge` keyword holding
/// a lossless JSON record, and a `parameters` keyword holding an
/// AUTOMATIC1111-compatible string. This is a **pure** parser — it never touches
/// the diffusion engine; the app uses it to reconstruct prompts/seeds when it
/// loads an existing library folder's PNGs into the gallery.
///
/// The chunk writer it mirrors is image-forge `internal/engine/pngmeta.go`
/// (`encodeTextChunk`): `tEXt` when the text is Latin-1-safe, else `iTXt` (UTF-8,
/// so Unicode prompts round-trip). The JSON shape is image-forge
/// `internal/cli/metadata.go` (`imgforgeMeta`).
struct PngMetadata: Equatable {
    var prompt: String?
    var negative: String?
    var seed: Int64?
    var width: Int?
    var height: Int?
    var model: String?
    var sampler: String?
    var scheduler: String?
    var steps: Int?
    var cfg: Double?

    /// Parse metadata from raw PNG bytes. Returns nil when the data isn't a PNG or
    /// carries no recognizable `image-forge` / `parameters` text chunk.
    static func read(_ data: Data) -> PngMetadata? {
        guard let chunks = textChunks(in: data) else { return nil }
        if let json = chunks["image-forge"], let meta = fromForgeJSON(json) {
            return meta
        }
        if let params = chunks["parameters"] {
            return fromA1111(params)
        }
        return nil
    }

    /// Parse metadata from a PNG on disk. Returns nil if the file can't be read or
    /// has no recognizable metadata.
    static func read(contentsOf url: URL) -> PngMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return read(data)
    }

    // MARK: - Chunk walking

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Walk PNG chunks (`length(4 BE) + type(4) + data + crc(4)`) collecting the
    /// text carried by every `tEXt` / `iTXt` chunk, keyed by keyword. CRC bytes are
    /// skipped, not verified. Returns nil when the signature doesn't match.
    private static func textChunks(in data: Data) -> [String: String]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { return nil }

        var chunks: [String: String] = [:]
        var i = 8
        while i + 8 <= bytes.count {
            let len = Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16
                | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            let typeStart = i + 4
            let dataStart = typeStart + 4
            guard len >= 0, dataStart + len + 4 <= bytes.count else { break }
            let type = String(bytes: bytes[typeStart..<dataStart], encoding: .ascii) ?? ""
            let chunkData = Array(bytes[dataStart..<dataStart + len])
            switch type {
            case "tEXt":
                if let (k, v) = parseTEXt(chunkData) { chunks[k] = v }
            case "iTXt":
                if let (k, v) = parseITXt(chunkData) { chunks[k] = v }
            default:
                break
            }
            i = dataStart + len + 4 // advance past data + crc
            if type == "IEND" { break }
        }
        return chunks.isEmpty ? nil : chunks
    }

    /// `tEXt`: `keyword \0 latin1(text)`.
    private static func parseTEXt(_ d: [UInt8]) -> (String, String)? {
        guard let nul = d.firstIndex(of: 0) else { return nil }
        let keyword = String(bytes: d[0..<nul], encoding: .isoLatin1) ?? ""
        let text = String(bytes: d[(nul + 1)...], encoding: .isoLatin1) ?? ""
        return keyword.isEmpty ? nil : (keyword, text)
    }

    /// `iTXt`: `keyword \0 compFlag compMethod langtag \0 transkw \0 utf8(text)`.
    /// Compressed iTXt (compFlag != 0) is ignored — image-forge never compresses.
    private static func parseITXt(_ d: [UInt8]) -> (String, String)? {
        guard let nul = d.firstIndex(of: 0) else { return nil }
        let keyword = String(bytes: d[0..<nul], encoding: .isoLatin1) ?? ""
        var j = nul + 1
        guard j + 2 <= d.count else { return nil }
        let compFlag = d[j]
        j += 2 // skip compression flag + method
        guard let langNul = d[j...].firstIndex(of: 0) else { return nil }
        j = langNul + 1
        guard let transNul = d[j...].firstIndex(of: 0) else { return nil }
        j = transNul + 1
        guard compFlag == 0 else { return nil }
        let text = String(bytes: d[j...], encoding: .utf8) ?? ""
        return keyword.isEmpty ? nil : (keyword, text)
    }

    // MARK: - image-forge JSON

    /// The subset of `imgforgeMeta` (image-forge `internal/cli/metadata.go`) the GUI
    /// needs. All fields optional so a partial/older record still decodes.
    private struct ForgeJSON: Decodable {
        var prompt: String?
        var negative: String?
        var seed: Int64?
        var steps: Int?
        var cfg: Double?
        var width: Int?
        var height: Int?
        var model: String?
        var sampler: String?
        var scheduler: String?

        enum CodingKeys: String, CodingKey {
            case prompt, negative, seed, steps, cfg, width, height, model, sampler, scheduler
        }
    }

    private static func fromForgeJSON(_ text: String) -> PngMetadata? {
        guard let data = text.data(using: .utf8),
              let j = try? JSONDecoder().decode(ForgeJSON.self, from: data) else { return nil }
        return PngMetadata(
            prompt: nonEmpty(j.prompt),
            negative: nonEmpty(j.negative),
            seed: j.seed,
            width: j.width,
            height: j.height,
            model: nonEmpty(j.model),
            sampler: nonEmpty(j.sampler),
            scheduler: nonEmpty(j.scheduler),
            steps: j.steps,
            cfg: j.cfg
        )
    }

    // MARK: - AUTOMATIC1111 fallback

    /// Parse the A1111 `parameters` string (image-forge `a1111Parameters`):
    /// line 1 is the prompt, an optional `Negative prompt:` line, then a settings
    /// line of comma-joined `Key: value` pairs (`Seed`, `Size: WxH`, `Steps`,
    /// `CFG scale`, `Model`, `Sampler`, …).
    private static func fromA1111(_ text: String) -> PngMetadata {
        let lines = text.components(separatedBy: "\n")
        var meta = PngMetadata()
        meta.prompt = nonEmpty(lines.first)

        if let neg = lines.first(where: { $0.hasPrefix("Negative prompt:") }) {
            meta.negative = nonEmpty(String(neg.dropFirst("Negative prompt:".count))
                .trimmingCharacters(in: .whitespaces))
        }

        guard let settings = lines.first(where: { $0.hasPrefix("Steps:") || $0.contains("Seed:") }) else {
            return meta
        }
        for pair in settings.components(separatedBy: ", ") {
            guard let sep = pair.range(of: ": ") else { continue }
            let key = String(pair[..<sep.lowerBound])
            let value = String(pair[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "Seed": meta.seed = Int64(value)
            case "Steps": meta.steps = Int(value)
            case "CFG scale": meta.cfg = Double(value)
            case "Sampler": meta.sampler = nonEmpty(value)
            case "Model": meta.model = nonEmpty(value)
            case "Size":
                let wh = value.split(separator: "x")
                if wh.count == 2 { meta.width = Int(wh[0]); meta.height = Int(wh[1]) }
            default: break
            }
        }
        return meta
    }

    /// nil for nil/empty strings, so absent metadata fields stay nil.
    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }
}
