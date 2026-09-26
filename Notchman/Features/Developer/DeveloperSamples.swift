import Foundation

/// Realistic test content for the developer screen.
enum DeveloperSamples {
    struct Sample: Identifiable {
        let id = UUID()
        let name: String
        let source: SourceType
        let text: String
    }

    static let all: [Sample] = [
        Sample(name: "ChatGPT answer (markdown + code)", source: .chatGPT, text: chatGPT),
        Sample(name: "Reddit post", source: .reddit, text: reddit),
        Sample(name: "Email", source: .email, text: email),
    ]

    static let chatGPT = """
    ## Architecture

    Great question! Here's how I'd structure a **SwiftUI** app that needs to play audio in the background:

    1. **Keep playback out of your views.** Create a `PlaybackManager` that owns the audio engine.
    2. **Share it app-wide** using the environment, so it survives navigation.
    3. **Persist progress** every few seconds with SwiftData.

    ### Example

    ```swift
    @Observable
    final class PlaybackManager {
        var isPlaying = false
        func play() { isPlaying = true }
    }
    ```

    > Note: you must enable the *Audio, AirPlay, and Picture in Picture* background mode, or speech stops when the screen locks.

    | Option | Pros | Cons |
    |---|---|---|
    | AVSpeechSynthesizer | Free, offline | Robotic voices |
    | Cloud TTS | Natural | Costs money |

    For more details see https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer or [Apple's audio guide](https://developer.apple.com/audio/).

    That's it — ~3 steps and you're done! 🚀
    """

    static let reddit = """
    I quit my job to build an app for 18 months. Here's what I learned.

    TL;DR: ship earlier, talk to users, and don't build features nobody asked for.

    When I started, I was convinced the product needed 12 features before launch. I spent the first 9 months building all of them. When I finally launched, users only cared about 2 of them.

    The biggest mistake was not talking to anyone. I assumed I knew what people wanted. I didn't.

    Edit: wow, this blew up. To answer the most common question: yes, I'd do it again, but I'd give myself a hard deadline of 3 months to launch.
    """

    static let email = """
    From: Sarah Chen
    To: Product Team
    Subject: Q3 launch plan — decisions needed by Friday

    Hi all,

    Quick update on the Q3 launch. We're on track for September 18, but we need two decisions by this Friday or the date slips.

    First, pricing. Finance recommends $4.99 per month with a 7-day trial. Marketing prefers $3.99. Please weigh in.

    Second, the onboarding flow. Design has two versions ready; the shorter one tested 22% better for completion.

    Action items: Mark, confirm the App Store assets by Wednesday. Priya, get legal sign-off on the new privacy text.

    Thanks,
    Sarah
    """
}
