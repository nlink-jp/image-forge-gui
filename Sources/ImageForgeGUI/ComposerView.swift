import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// hires override presented in the Composer. `Default` sends no `hires` field so
/// the engine uses the model profile's default.
enum HiresMode: String, CaseIterable, Identifiable {
    case standard = "Default"
    case off = "Off"
    case auto = "Auto"
    case on = "On"

    var id: String { rawValue }

    /// Map a request's `hires` value ("off"/"auto"/"on"/nil) back to a mode.
    init(value: String?) {
        switch value {
        case "off": self = .off
        case "auto": self = .auto
        case "on": self = .on
        default: self = .standard
        }
    }

    /// The `hires` value sent to serve (nil for the profile default).
    var value: String? {
        switch self {
        case .standard: return nil
        case .off: return "off"
        case .auto: return "auto"
        case .on: return "on"
        }
    }
}

/// One LoRA selection in the Composer: which installed LoRA, and its weight.
/// LoRAs are applied per render (no model reload), so several can be stacked.
struct LoRARow: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var weight: Double = 1.0
}

/// The left-hand composer: prompt, negative, model, and the core generation
/// parameters. Numeric fields left blank mean "use the model profile default".
struct ComposerView: View {
    @EnvironmentObject var model: AppModel

    @State private var prompt = ""
    @State private var negative = ""
    @State private var selectedModel: String?
    @State private var randomSeed = true
    @State private var seedText = ""
    @State private var stepsText = ""
    @State private var cfgText = ""
    @State private var width: Int?
    @State private var height: Int?
    @State private var count = 1
    @State private var hires: HiresMode = .standard
    @State private var samplerOverride = ""   // "" = model profile default
    @State private var schedulerOverride = "" // "" = engine/profile default
    @State private var clipSkipOverride = 0    // 0 = model profile default
    @State private var initImageURL: URL?      // set => img2img
    @State private var strength: Double = 0.6  // img2img denoise strength
    @State private var loraRows: [LoRARow] = []
    /// Hide questionable/explicit models from the picker when on.
    @AppStorage("safeOnly") private var safeOnly = false
    /// Merge the selected LoRAs' trigger words into the prompt at generation time
    /// (kept out of the prompt field to avoid clutter/accumulation).
    @AppStorage("autoAddTriggers") private var autoAddTriggers = true

    @FocusState private var promptFocused: Bool

    /// Common SDXL-friendly dimensions; nil = the model profile default.
    private static let sizes: [Int] = [512, 640, 768, 832, 896, 1024, 1152, 1216, 1344]
    /// sd.cpp sampler / scheduler names (empty selection = the profile default).
    private static let samplers = ["euler_a", "euler", "heun", "dpm2", "dpm++2s_a",
                                   "dpm++2m", "dpm++2mv2", "ipndm", "ipndm_v", "lcm",
                                   "ddim_trailing", "tcd"]
    private static let schedulers = ["discrete", "karras", "exponential", "ays",
                                     "sgm_uniform", "simple", "kl_optimal", "gits",
                                     "smoothstep", "beta"]

    private var diffusionModels: [ModelInfo] {
        model.models.filter { $0.isDiffusion && (!safeOnly || ($0.rating ?? "") == "safe") }
    }

    /// Picker label: "name — ARCH", plus the catalog content rating for non-safe
    /// entries (`· questionable` / `· explicit`).
    private func modelLabel(_ m: ModelInfo) -> String {
        var s = "\(m.name) — \(m.arch.uppercased())"
        if let r = m.rating, !r.isEmpty, r != "safe" { s += "  ·  \(r)" }
        return s
    }

    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isGenerating
            && !model.isUpscaling
            && selectedModel != nil
    }

    var body: some View {
        Form {
            Section("Prompt") {
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 150)
                    .focused($promptFocused)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Negative prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $negative)
                        .font(.body)
                        .frame(minHeight: 90)
                }
            }

            Section("Model") {
                Picker("Model", selection: $selectedModel) {
                    if diffusionModels.isEmpty {
                        Text(safeOnly ? "No safe models installed" : "No models installed")
                            .tag(String?.none)
                    }
                    ForEach(diffusionModels) { m in
                        Text(modelLabel(m)).tag(String?.some(m.name))
                    }
                }
                .disabled(diffusionModels.isEmpty)
                Toggle("Safe only (hide questionable / explicit)", isOn: $safeOnly)
            }

            Section("LoRA") {
                loraControl
            }

            Section("Init image (img2img)") {
                initImageControl
            }

            Section("Parameters") {
                Toggle("Random seed", isOn: $randomSeed)
                if !randomSeed {
                    TextField("Seed", text: $seedText)
                        .textFieldStyle(.roundedBorder)
                }
                TextField("Steps (default)", text: $stepsText)
                    .textFieldStyle(.roundedBorder)
                TextField("CFG (default)", text: $cfgText)
                    .textFieldStyle(.roundedBorder)
                Picker("Width", selection: $width) {
                    Text("Default").tag(Int?.none)
                    ForEach(Self.sizes, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                Picker("Height", selection: $height) {
                    Text("Default").tag(Int?.none)
                    ForEach(Self.sizes, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                Picker("Hires", selection: $hires) {
                    ForEach(HiresMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Count: \(count)", value: $count, in: 1...16)
            }

            Section("Advanced") {
                Picker("Sampler", selection: $samplerOverride) {
                    Text("Profile default").tag("")
                    ForEach(Self.samplers, id: \.self) { Text($0).tag($0) }
                }
                Picker("Scheduler", selection: $schedulerOverride) {
                    Text("Default").tag("")
                    ForEach(Self.schedulers, id: \.self) { Text($0).tag($0) }
                }
                Picker("Clip skip", selection: $clipSkipOverride) {
                    Text("Profile default").tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
            }

            Section {
                if model.isGenerating {
                    Button(role: .destructive, action: model.cancelGeneration) {
                        Label("Cancel", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button(action: generate) {
                        Label("Generate", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canGenerate)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: syncSelectedModel)
        .onChange(of: model.models) { _, _ in syncSelectedModel(); pruneIncompatibleLoRAs() }
        .onChange(of: safeOnly) { _, _ in syncSelectedModel() }
        // A LoRA is bound to its base architecture — switching models drops the
        // ones that no longer apply.
        .onChange(of: selectedModel) { _, _ in pruneIncompatibleLoRAs() }
        .onChange(of: model.newGenerationTick) { _, _ in resetComposer() }
        .onChange(of: model.reuseTick) { _, _ in applyReuse() }
        .onChange(of: model.setInitTick) { _, _ in
            if let u = model.pendingInitURL { initImageURL = u }
        }
    }

    // MARK: - LoRA

    /// The base model's architecture (LoRAs are bound to it).
    private var selectedArch: String { model.arch(ofModel: selectedModel) }

    /// Installed LoRAs compatible with the selected base model.
    private var compatibleLoRAs: [ModelInfo] {
        selectedModel == nil ? [] : model.loras(forArch: selectedArch)
    }

    /// Compatible LoRAs not already stacked (so each is offered once).
    private var unusedLoRAs: [ModelInfo] {
        let used = Set(loraRows.map(\.name))
        return compatibleLoRAs.filter { !used.contains($0.name) }
    }

    /// The `loras` payload sent to serve: "<path>:<weight>" per row.
    private var loraPayload: [String] {
        AppModel.loraPayload(
            selections: loraRows.map { (name: $0.name, weight: $0.weight) },
            models: model.models)
    }

    @ViewBuilder private var loraControl: some View {
        if compatibleLoRAs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedModel == nil
                     ? "Select a model first."
                     : "No LoRAs installed for \(selectedArch.uppercased()).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Install one with:  image-forge models pull lcm-lora-sdxl")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach($loraRows) { $row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Picker("", selection: $row.name) {
                            ForEach(compatibleLoRAs) { Text($0.name).tag($0.name) }
                        }
                        .labelsHidden()
                        Button {
                            loraRows.removeAll { $0.id == row.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this LoRA")
                    }
                    HStack(spacing: 8) {
                        Text("Weight").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $row.weight, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f", row.weight))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    let triggers = model.triggerWords(forLoRA: row.name)
                    if !triggers.isEmpty {
                        Text("trigger: \(triggers.joined(separator: ", "))")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            Button { addLoRA() } label: {
                Label("Add LoRA", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(unusedLoRAs.isEmpty)

            triggerControl
        }
    }

    /// Section-level trigger handling: rather than editing the prompt when a LoRA
    /// is picked (which piles up stale tokens), the selected LoRAs' trigger words
    /// are shown here and merged into the prompt only at generation — toggleable,
    /// so the user can instead place them by hand.
    @ViewBuilder private var triggerControl: some View {
        if !selectedLoRATriggers.isEmpty {
            let joined = selectedLoRATriggers.joined(separator: ", ")
            Divider()
            Toggle("Add trigger words automatically", isOn: $autoAddTriggers)
                .font(.callout)
            // A read-only, selectable box holding just the trigger words, plus a
            // one-click Copy — so they're easy to paste in when auto-add is off.
            HStack(spacing: 6) {
                Text(joined)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.3)))
                Button { setClipboard(joined) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy trigger words")
            }
            Text(autoAddTriggers
                 ? "Prepended when you Generate (words already in the prompt are skipped)."
                 : "Not added — paste these into your prompt yourself, or the LoRA won't take effect.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The de-duplicated trigger words of all stacked LoRAs (not in the prompt).
    private var selectedLoRATriggers: [String] {
        AppModel.combinedTriggerWords(forLoRAs: loraRows.map(\.name), models: model.models)
    }

    /// The prompt actually sent: with trigger words merged in when the toggle is on.
    private var effectivePrompt: String {
        autoAddTriggers
            ? AppModel.prompt(prompt, insertingTriggers: selectedLoRATriggers)
            : prompt
    }

    private func addLoRA() {
        guard let next = unusedLoRAs.first else { return }
        loraRows.append(LoRARow(name: next.name))
    }

    /// Drop stacked LoRAs that don't match the (newly selected) base model's arch.
    private func pruneIncompatibleLoRAs() {
        let ok = Set(compatibleLoRAs.map(\.name))
        loraRows.removeAll { !ok.contains($0.name) }
    }

    /// The init-image control shown in the "Init image (img2img)" section: a
    /// drop target + file picker when empty, or a thumbnail + strength slider +
    /// Clear when set. Dropping an image file (from Finder or the gallery via
    /// "Use as Init Image") sets it.
    @ViewBuilder private var initImageControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = initImageURL {
                HStack(alignment: .top, spacing: 10) {
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) }
                        placeholder: { ProgressView() }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(url.lastPathComponent)
                            .font(.caption).lineLimit(1).truncationMode(.middle)
                        Button("Clear") { initImageURL = nil }.controlSize(.small)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Text("Strength").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $strength, in: 0.05...1.0, step: 0.05)
                    Text(String(format: "%.2f", strength))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            } else {
                Button { chooseInitImage() } label: {
                    Label("Choose or drop an image…", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Text("Generate variations from an existing image. Leave empty for txt2img.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: isImageFile) else { return false }
            initImageURL = url
            return true
        }
    }

    /// Default the picker to the first diffusion model once the list loads.
    private func syncSelectedModel() {
        if selectedModel == nil || !diffusionModels.contains(where: { $0.name == selectedModel }) {
            selectedModel = diffusionModels.first?.name
        }
    }

    private func resetComposer() {
        prompt = ""
        negative = ""
        seedText = ""
        stepsText = ""
        cfgText = ""
        width = nil
        height = nil
        count = 1
        hires = .standard
        samplerOverride = ""
        schedulerOverride = ""
        clipSkipOverride = 0
        initImageURL = nil
        strength = 0.6
        loraRows = []
        randomSeed = true
        promptFocused = true
    }

    /// Load a gallery image's parameters (from AppModel.pendingReuse) into the
    /// composer fields. promptOnly loads just the prompt + negative.
    private func applyReuse() {
        guard let (p, promptOnly) = model.pendingReuse else { return }
        prompt = p.prompt
        negative = p.negative ?? ""
        if !promptOnly {
            if let m = p.model, diffusionModels.contains(where: { $0.name == m }) {
                selectedModel = m
            }
            if let s = p.seed, s >= 0 {
                randomSeed = false
                seedText = String(s)
            } else {
                randomSeed = true
                seedText = ""
            }
            stepsText = p.steps.map(String.init) ?? ""
            cfgText = p.cfg.map { String(format: "%g", $0) } ?? ""
            width = p.width
            height = p.height
            samplerOverride = p.sampler ?? ""
            schedulerOverride = p.scheduler ?? ""
            clipSkipOverride = p.clipSkip ?? 0
            hires = HiresMode(value: p.hires)
            if let ip = p.initPath, !ip.isEmpty, FileManager.default.fileExists(atPath: ip) {
                initImageURL = URL(fileURLWithPath: ip)
                strength = p.strength ?? 0.6
            } else {
                initImageURL = nil
            }
        }
        promptFocused = true
    }

    private func generate() {
        model.generate(
            prompt: effectivePrompt,
            negative: negative.isEmpty ? nil : negative,
            model: selectedModel,
            seed: randomSeed ? nil : Int64(seedText.trimmingCharacters(in: .whitespaces)),
            randomSeed: randomSeed,
            steps: Int(stepsText.trimmingCharacters(in: .whitespaces)),
            cfg: Double(cfgText.trimmingCharacters(in: .whitespaces)),
            width: width,
            height: height,
            count: count,
            hires: hires.value,
            sampler: samplerOverride.isEmpty ? nil : samplerOverride,
            scheduler: schedulerOverride.isEmpty ? nil : schedulerOverride,
            clipSkip: clipSkipOverride == 0 ? nil : clipSkipOverride,
            initPath: initImageURL?.path,
            strength: initImageURL == nil ? nil : strength,
            loras: loraPayload.isEmpty ? nil : loraPayload
        )
    }

    /// Present an open panel to pick an init image for img2img.
    private func chooseInitImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.prompt = "Choose"
        panel.message = "Choose an init image for img2img"
        if panel.runModal() == .OK, let url = panel.url { initImageURL = url }
    }

    /// True for a file URL with a raster-image extension (drop filter).
    private func isImageFile(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "webp", "heic", "bmp", "gif", "tif", "tiff"]
            .contains(url.pathExtension.lowercased())
    }
}
