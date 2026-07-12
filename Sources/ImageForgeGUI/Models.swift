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
    var mask: String? = nil         // inpaint mask, absolute path (with initPath): white=regenerate, black=keep
    /// ControlNet model to steer generation (json: control_net). A resolved file
    /// path (so an older bundled CLI that can't resolve names still works). Loaded
    /// with the base model — changing it reloads the base (ADR-0006).
    var controlNet: String? = nil
    var control: String? = nil          // control image, absolute path
    var controlStrength: Double? = nil  // json: control_strength
    var canny: Bool? = nil              // edge-preprocess the control image
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
        case strength, mask
        case controlNet = "control_net"
        case control
        case controlStrength = "control_strength"
        case canny
        case loras, output
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
    /// Credit text to give when the license requires attribution (json:
    /// attribution). Present only for models flagged `attribution`.
    var attribution: String?
    /// The model's source web page — its Civitai model page or Hugging Face repo
    /// (json: page_url). The CLI derives it from the catalog; a front-end offers
    /// an "open model page" link. Absent for a user-local model not in the catalog.
    var pageURL: String?

    var id: String { name }

    /// The source page as a URL, if one is known and well-formed.
    var pageLink: URL? {
        guard let s = pageURL, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Whether this model's license carries a notable restriction to highlight.
    var hasLicenseFlags: Bool { !(licenseFlags ?? []).isEmpty }

    /// The credit line to give for this model, or nil when none is required.
    var creditText: String? {
        guard let a = attribution, !a.isEmpty else { return nil }
        return a
    }

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
        case attribution
        case pageURL = "page_url"
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

// MARK: - Catalog entry

/// One curated catalog model, as emitted by `image-forge models list --catalog
/// --json`. Matches the `catalogView` shape in image-forge `internal/cli/models.go`.
/// Unknown keys are ignored. Drives the Manage Models window (ADR-0001).
struct CatalogEntry: Codable, Identifiable, Equatable {
    var name: String
    var arch: String
    var kind: String?           // "" (diffusion) | upscaler | lora | controlnet
    var rating: String?
    var license: String?
    var minRAMGB: Int?          // json: min_ram_gb
    var recRAMGB: Int?          // json: rec_ram_gb
    var multiComponent: Bool?   // json: multi_component
    var needsOptIn: Bool?       // json: needs_opt_in — questionable/explicit rating
    var experimental: Bool?
    var installed: Bool?
    var notes: String?
    var licenseFlags: [String]? // json: license_flags
    /// The model's source web page — its Civitai model page or Hugging Face repo
    /// (json: page_url). Used for an "open model page" link.
    var pageURL: String?

    var id: String { name }

    /// The source page as a URL, if one is known and well-formed.
    var pageLink: URL? {
        guard let s = pageURL, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Whether installing this entry requires the NSFW opt-in (`--allow-nsfw`).
    var requiresOptIn: Bool { needsOptIn ?? false }

    /// Whether this entry is already installed (safe default: false).
    var isInstalled: Bool { installed ?? false }

    /// A base diffusion model (empty/absent kind) vs. an auxiliary kind.
    var isDiffusion: Bool { (kind ?? "").isEmpty }

    /// Short "kind" label for display: diffusion models show their arch; auxiliary
    /// kinds show the kind (LoRA / ControlNet / upscaler).
    var kindLabel: String {
        switch kind ?? "" {
        case "", "diffusion": return arch.uppercased()
        case let k: return k.capitalized
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, arch, kind, rating, license
        case minRAMGB = "min_ram_gb"
        case recRAMGB = "rec_ram_gb"
        case multiComponent = "multi_component"
        case needsOptIn = "needs_opt_in"
        case experimental, installed, notes
        case licenseFlags = "license_flags"
        case pageURL = "page_url"
    }

    /// Decode the catalog array from `image-forge models list --catalog --json`
    /// (a bare JSON array), tolerating the `--all` wrapper shape as a fallback.
    static func decodeCatalog(from data: Data) throws -> [CatalogEntry] {
        let dec = JSONDecoder()
        if let arr = try? dec.decode([CatalogEntry].self, from: data) {
            return arr
        }
        struct Wrapper: Decodable { let catalog: [CatalogEntry]? }
        return (try dec.decode(Wrapper.self, from: data)).catalog ?? []
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
