# AI Voice

A macOS menubar app for voice-to-text transcription. Record audio with a global hotkey, transcribe with either OpenAI's transcription API or local WhisperKit/Core ML, and auto-paste the result into your active application.

## Features

- Push-to-talk global hotkey (configurable)
- Apple-style transcription setting: Whisper OAI or Local Model
- Auto-paste into active app after transcription
- Recording overlay with visual aura effect
- Status island indicator during recording
- Transcription history with playback
- Multi-language support (auto-detect, Ukrainian, English, Russian, etc.)
- Native macOS app — no Electron, no web views

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.9+
- OpenAI API key for Whisper OAI transcription
- Network access for the first on-device model download; local transcription runs on device after models are cached

## Build & Install

```bash
bash build.sh
cp -r AI\ Voice.app ~/Applications/
open ~/Applications/AI\ Voice.app
```

## Setup

1. Launch the app — it appears in your menubar
2. Open Settings and choose Whisper OAI or Local Model
3. Grant Accessibility and Microphone permissions when prompted

Defaults:
- Whisper OAI: `whisper-1`.
- Local Model: WhisperKit `large-v3-v20240930_626MB`, recommended for maximum multilingual accuracy on Apple Silicon.

On-device mode does not send transcription audio to a remote API.

## Tests

```bash
swift test
```

## License

[MIT](LICENSE)
