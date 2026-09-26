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

    private var effectiveLanguage: String { AppSettings().language }

    var body: some View {
        Form {
            voiceSection
            playbackSection
            quickListenSection
            privacySection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .toolbar(.visible, for: .navigationBar)
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

    // MARK: TL;DR

    @Environment(AppEnvironment.self) private var env

    private var quickListenSection: some View {
        Section {
            Picker("Summary Length", selection: $quickListenDuration) {
                ForEach(QuickListenDuration.allCases) { duration in
                    Text(duration.label).tag(duration.rawValue)
                }
            }
            if let usage = env.usage {
                LabeledContent("This month", value: "\(usage.remaining) of \(usage.limit) left")
                LabeledContent("Plan", value: usage.planName)
            }
            if env.usage?.plan != "proplus" {
                Button("See Plans") { router.sheet = .paywall }
            }
        } header: {
            Text("TL;DR")
        } footer: {
            Text("TL;DRs are made by Notchman's AI. Free includes 10 a month, Pro 100 and Pro+ 250. If you're offline, Notchman makes a shorter summary on your iPhone.")
        }
        .task { await env.refreshUsage() }
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
            Text("History stays on this iPhone. Speech uses Apple's built-in voices. External AI is only used if you choose it.")
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
