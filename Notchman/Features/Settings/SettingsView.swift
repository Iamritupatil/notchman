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
    @AppStorage(SettingsKey.quickListenDuration, store: AppGroup.defaults)
    private var quickListenDuration = AppSettings.Default.quickListenDuration
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = true
    @AppStorage(SettingsKey.restInDynamicIsland, store: AppGroup.defaults) private var restInDynamicIsland = true

    private var effectiveLanguage: String { AppSettings().language }

    var body: some View {
        Form {
            voiceSection
            playbackSection
            quickListenSection
            if developerMode {
                cloudCheckSection
            }
            privacySection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.sky.ignoresSafeArea())
        .pushedPage("Settings")
        .onChange(of: defaultSpeed) { _, newValue in
            playback.setSpeed(newValue)
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section {
            if NotchmanCloud.isAvailable {
                NavigationLink {
                    CloudVoicePickerView()
                } label: {
                    LabeledContent("Voice", value: CloudVoice.voice(id: playback.voiceID).name)
                }
            } else {
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
            }
            Picker("Speech Speed", selection: $defaultSpeed) {
                ForEach(PlaybackSpeed.options, id: \.self) { speed in
                    Text(PlaybackSpeed.label(speed)).tag(speed)
                }
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(NotchmanCloud.isAvailable
                 ? "One natural voice for TL;DRs and full reads, in the language of the message."
                 : "Notchman switches to a matching voice when a message is clearly in another language.")
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
            Toggle("Keep Notchman in the Dynamic Island", isOn: $restInDynamicIsland)
                .onChange(of: restInDynamicIsland) { _, on in playback.setRestsInDynamicIsland(on) }
            Toggle("Skip Code Blocks", isOn: $skipCodeBlocks)
            Toggle("Clean Markdown", isOn: $cleanMarkdown)
            Toggle("Share Starts a TL;DR", isOn: $autoStartFromShare)
        } header: {
            Text("Playback")
        } footer: {
            Text("On: Share → Notchman plays a TL;DR straight away, no extra taps. Off: you choose TL;DR or the full message. Cleaning settings apply to newly added items.")
        }
    }

    // MARK: TL;DR

    @Environment(AppEnvironment.self) private var env

    private var quickListenSection: some View {
        Section {
            if let usage = env.usage {
                LabeledContent("This month", value: "\(usage.remaining) of \(usage.limit) left")
                if FeatureFlags.paidPlans {
                    LabeledContent("Plan", value: usage.planName)
                }
            }
            if FeatureFlags.paidPlans, env.usage?.plan != "proplus" {
                Button("See Plans") { router.sheet = .paywall }
            }
        } header: {
            Text("TL;DR")
        } footer: {
            Text(NotchmanCloud.isAvailable
                 ? "A TL;DR keeps every key point and is as long as it needs to be, in the language of the message."
                 : FeatureFlags.paidPlans
                 ? "Free includes 10 TL;DRs a month, made on your iPhone. Pro (40 a month) and Pro+ (100) use Notchman's AI and a natural voice, in the language of the message. Listening to the full message is always unlimited."
                 : "You get 10 TL;DRs a month, made right on your iPhone. Nothing you read is sent anywhere. Listening to the full message is always unlimited.")
        }
        .task { await env.refreshUsage() }
    }

    // MARK: Cloud check (beta)

    @AppStorage("developerMode", store: AppGroup.defaults) private var developerMode = false
    @State private var versionTaps = 0
    @State private var cloudSteps: [CloudDiagnostics.Step] = []
    @State private var checkingCloud = false

    private var cloudCheckSection: some View {
        Section {
            Button {
                checkingCloud = true
                cloudSteps = []
                Task {
                    cloudSteps = await CloudDiagnostics.run()
                    checkingCloud = false
                }
            } label: {
                HStack {
                    Text("Check Cloud")
                    Spacer()
                    if checkingCloud { ProgressView() }
                }
            }
            .disabled(checkingCloud)

            ForEach(cloudSteps) { step in
                VStack(alignment: .leading, spacing: 2) {
                    Label(step.name, systemImage: step.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(step.ok ? Color.green : Color.red)
                    Text(step.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    if !step.ok {
                        DisclosureGroup("Technical details") {
                            Text(step.detail)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.tertiaryText)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }
                }
            }

            if cloudSteps.isEmpty, let problem = CloudDiagnostics.lastProblem {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last problem").font(.caption.weight(.semibold))
                    Text(CloudDiagnostics.friendly(problem)).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Tests each step of a Groq + ElevenLabs TL;DR. Screenshot the result if something is red.")
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyDetailsView()
            } label: {
                Label("How Notchman handles your data", systemImage: "hand.raised.fill")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text(NotchmanCloud.isAvailable
                 ? "History stays on this iPhone. Message text goes to Groq (TL;DR) and ElevenLabs (voice) only to make your audio."
                 : "History stays on this iPhone. Speech uses Apple's built-in voices.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            #if DEBUG
            Button("Try Notchman (developer)") { router.sheet = .tryNotchman }
            #endif
            Button("Show Onboarding Again") { hasCompletedOnboarding = false }
            LabeledContent("Version", value: Bundle.main.appVersion)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Seven taps toggle the hidden developer tools (Check Cloud).
                    versionTaps += 1
                    if versionTaps >= 7 {
                        versionTaps = 0
                        developerMode.toggle()
                        Haptics.success()
                    }
                }
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
