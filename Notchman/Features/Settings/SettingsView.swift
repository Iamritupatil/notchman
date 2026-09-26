import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PlaybackManager.self) private var playback

    @AppStorage(SettingsKey.voiceIdentifier, store: AppGroup.defaults) private var voiceIdentifier = ""
    @AppStorage(SettingsKey.language, store: AppGroup.defaults) private var language = ""
    @AppStorage(SettingsKey.defaultSpeed, store: AppGroup.defaults) private var defaultSpeed = AppSettings.Default.speed
    @AppStorage(SettingsKey.skipCodeBlocks, store: AppGroup.defaults) private var skipCodeBlocks = AppSettings.Default.skipCodeBlocks
    @AppStorage(SettingsKey.cleanMarkdown, store: AppGroup.defaults) private var cleanMarkdown = AppSettings.Default.cleanMarkdown
    @AppStorage(SettingsKey.autoStartFromShare, store: AppGroup.defaults)
    private var autoStartFromShare = AppSettings.Default.autoStartFromShare
    @AppStorage(SettingsKey.quickListenProvider, store: AppGroup.defaults)
    private var quickListenProvider = AppSettings.Default.quickListenProvider
    @AppStorage(SettingsKey.quickListenDuration, store: AppGroup.defaults)
    private var quickListenDuration = AppSettings.Default.quickListenDuration
    @AppStorage(SettingsKey.openAIModel, store: AppGroup.defaults) private var openAIModel = AppSettings.Default.openAIModel
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = true

    @State private var apiKey = KeychainStore.string(for: KeychainStore.openAIKey) ?? ""

    private var providerKind: QuickListenProviderKind {
        QuickListenProviderKind(rawValue: quickListenProvider) ?? .off
    }

    private var effectiveLanguage: String { AppSettings().language }

    var body: some View {
        Form {
            voiceSection
            playbackSection
            quickListenSection
            privacySection
            aboutSection
        }
        .navigationTitle("Settings")
        .onChange(of: defaultSpeed) { _, newValue in
            playback.setSpeed(newValue)
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section {
            NavigationLink {
                LanguagePickerView(selection: $language)
            } label: {
                LabeledContent("Default Language",
                               value: language.isEmpty ? "Automatic" : VoiceCatalog.displayName(for: language))
            }
            NavigationLink {
                VoicePickerView(language: effectiveLanguage, selection: $voiceIdentifier)
            } label: {
                LabeledContent("Voice", value: voiceName)
            }
            Picker("Speech Speed", selection: $defaultSpeed) {
                ForEach(PlaybackSpeed.options, id: \.self) { speed in
                    Text(PlaybackSpeed.label(speed)).tag(speed)
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text("Notchman switches to a matching voice when a message is clearly in another language.")
        }
    }

    private var voiceName: String {
        if !voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return voice.name
        }
        return "Automatic"
    }

    // MARK: Playback

    private var playbackSection: some View {
        Section {
            Toggle("Skip Code Blocks", isOn: $skipCodeBlocks)
            Toggle("Clean Markdown", isOn: $cleanMarkdown)
            Toggle("Auto-start from Share", isOn: $autoStartFromShare)
        } header: {
            Text("Playback")
        } footer: {
            Text("With auto-start on, sharing to Notchman starts reading right away instead of asking first. Cleaning settings apply to newly added items.")
        }
    }

    // MARK: Quick Listen

    private var quickListenSection: some View {
        Section {
            Picker("Provider", selection: $quickListenProvider) {
                ForEach(QuickListenProviderKind.allCases) { kind in
                    if kind != .appleIntelligence || AppleIntelligence.isAvailable {
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
            }
            if providerKind != .off {
                Picker("Summary Length", selection: $quickListenDuration) {
                    ForEach(QuickListenDuration.allCases) { duration in
                        Text(duration.label).tag(duration.rawValue)
                    }
                }
            }
            if providerKind == .openAI {
                SecureField("API Key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: apiKey) { _, newValue in
                        KeychainStore.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                          for: KeychainStore.openAIKey)
                    }
                TextField("Model", text: $openAIModel)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Quick Listen")
        } footer: {
            Text(quickListenFooter)
        }
    }

    private var quickListenFooter: String {
        switch providerKind {
        case .off:
            "Quick Listen turns long messages into a short spoken summary. It's off until you choose a provider."
        case .basic:
            "Picks the most important sentences on your iPhone. Nothing is sent anywhere."
        case .appleIntelligence:
            "Summarizes privately on your iPhone with Apple Intelligence."
        case .openAI:
            "Content you Quick Listen to is sent to OpenAI using your own API key, which is stored in your Keychain."
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section("Privacy") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Stored on this iPhone", systemImage: "iphone")
                    .font(.subheadline.weight(.semibold))
                Text("Your listening history lives only on this device. No account, no tracking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 10) {
                Label("Speech", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                Text("Reading aloud uses Apple's built-in speech voices, processed by iOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 10) {
                Label("AI summaries", systemImage: "bolt")
                    .font(.subheadline.weight(.semibold))
                Text("If you turn on an external Quick Listen provider, the text you summarize is sent to that provider. On-device options never send content anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            Button("Try Notchman") { router.sheet = .tryNotchman }
            Button("Show Onboarding Again") { hasCompletedOnboarding = false }
            LabeledContent("Version", value: Bundle.main.appVersion)
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
