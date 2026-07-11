import Foundation

// MARK: - Generation request

/// One line of the `image-forge serve` request protocol: a single JSON object
/// per line on the engine's stdin. Optional fields are *overrides* — when nil
/// they are omitted from the JSON so the engine falls back to the model
/// profile's default. Mirrors `serveRequest` in image-forge
/// `internal/cli/serve.go`.
///
/// `prompt` and `output` are always required (each generation writes to a unique
/// path the GUI assigns). The synthesized `Encodable` uses `encodeIfPresent` for
/// optionals, so nil fields never appear on the wire.
struct GenerationRequest: Codable, Equatable {
    var prompt: String
    var negative: String? = nil
    var model: String? = nil
    var seed: Int64? = nil          // -1 => the engine picks a random seed (reported back on `done`)
    var steps: Int? = nil
    var cfg: Double? = nil
    var width: Int? = nil
    var height: Int? = nil
    var sampler: String? = nil
    var scheduler: String? = nil
    var clipSkip: Int? = nil        // json: clip_skip
    var batch: Int? = nil
    var hires: String? = nil        // "auto" | "on" | "off"
    var initPath: String? = nil     // json: init — img2img source image
    var strength: Double? = nil     // img2img denoise strength
    /// LoRAs to apply, each `"<path>:<weight>"`. Applied per render (no model
    /// reload). We send resolved file paths rather than registry names so an
    /// older bundled CLI (which can't resolve names) still works.
    var loras: [String]? = nil
    var output: String              // absolute path the engine writes the PNG to

    enum CodingKeys: String, CodingKey {
        case prompt, negative, model, seed, steps, cfg, width, height
        case sampler, scheduler
        case clipSkip = "clip_skip"
        case batch, hires
        case initPath = "init"
        case strength, loras, output
    }
}

// MARK: - Serve events

/// One event line from `image-forge serve` stdout. Mirrors `engine.Event` in
/// image-forge `internal/engine/engine.go`. All fields but `kind` are optional
/// (the Go side marshals them `omitempty`).
struct ServeEvent: Decodable, Equatable {
    /// The event discriminator. `unknown` absorbs any future/unrecognized kind
    /// so decoding never fails on a value we don't model yet.
    enum Kind: String, Decodable, Equatable {
        case ready, load, progress, done, error, unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    var kind: Kind
    var progress: Double?   // 0…1 fraction, on `progress` / `done`
    var message: String?    // human text, on `ready` / `load` / `progress` / `error`
    var output: String?     // image path, on `done`
    var seed: Int64?        // seed used, on `done`
}

// MARK: - Model listing

/// One installed model, as emitted by `image-forge models list --json`. Matches
/// the `installedView` shape in image-forge `internal/cli/models.go`. Unknown
/// keys (e.g. `vae_path`, `multi_component`) are ignored by the decoder.
struct ModelInfo: Codable, Identifiable, Equatable {
    var name: String
    var arch: String
    var rating: String?
    var license: String?
    var path: String?
    var kind: String?       // "" (diffusion) or "upscaler"
    var inCatalog: Bool?    // json: in_catalog
    /// Prompt tokens that activate a LoRA (json: trigger_words). Absent → nil.
    /// Without them a LoRA loads but does nothing, so the Composer surfaces them.
    var triggerWords: [String]?
    /// Notable license restrictions (json: license_flags) — non-commercial /
    /// no-derivatives / attribution / share-alike. Empty/absent → permissive.
    var licenseFlags: [String]?

    var id: String { name }

    /// Whether this model's license carries a notable restriction to highlight.
    var hasLicenseFlags: Bool { !(licenseFlags ?? []).isEmpty }

    /// True for a base diffusion model (an empty/absent `kind`) — the Composer's
    /// model picker offers these only. The rest are auxiliary kinds (ADR-0006).
    var isDiffusion: Bool { (kind ?? "").isEmpty }

    /// A LoRA adapter, bound to the base `arch` it was trained against.
    var isLoRA: Bool { kind == "lora" }

    /// A ControlNet model, bound to the base `arch` it was trained against.
    var isControlNet: Bool { kind == "controlnet" }

    /// Whether this auxiliary model is compatible with a base model's architecture.
    func matchesArch(_ baseArch: String) -> Bool {
        arch.caseInsensitiveCompare(baseArch) == .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case name, arch, rating, license, path, kind
        case inCatalog = "in_catalog"
        case triggerWords = "trigger_words"
        case licenseFlags = "license_flags"
    }

    /// Decode the installed-model array from `image-forge models list --json`.
    /// The default (installed-only) output is a **bare JSON array**; `--all`
    /// wraps it as `{"installed":[…],"catalog":[…]}`. Both shapes are accepted.
    static func decodeInstalled(from data: Data) throws -> [ModelInfo] {
        let dec = JSONDecoder()
        if let arr = try? dec.decode([ModelInfo].self, from: data) {
            return arr
        }
        struct Wrapper: Decodable { let installed: [ModelInfo]? }
        return (try dec.decode(Wrapper.self, from: data)).installed ?? []
    }
}

// MARK: - Gallery item

/// A generated image in the session gallery: the PNG on disk plus the request
/// that produced it (for the inspector and, later, params-reuse).
struct GeneratedImage: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let prompt: String
    let seed: Int64?
    let params: GenerationRequest
    /// Actual on-disk pixel dimensions (PNG IHDR). Preferred over the request's
    /// width/height for display, which is the *requested* size and diverges after
    /// hires or upscale. nil until read from the file.
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
}
