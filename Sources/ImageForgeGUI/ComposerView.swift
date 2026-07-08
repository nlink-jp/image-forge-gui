import SwiftUI

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
    /// Hide questionable/explicit models from the picker when on.
    @AppStorage("safeOnly") private var safeOnly = false

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
        .onChange(of: model.models) { _, _ in syncSelectedModel() }
        .onChange(of: safeOnly) { _, _ in syncSelectedModel() }
        .onChange(of: model.newGenerationTick) { _, _ in resetComposer() }
        .onChange(of: model.reuseTick) { _, _ in applyReuse() }
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
        }
        promptFocused = true
    }

    private func generate() {
        model.generate(
            prompt: prompt,
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
            clipSkip: clipSkipOverride == 0 ? nil : clipSkipOverride
        )
    }
}
