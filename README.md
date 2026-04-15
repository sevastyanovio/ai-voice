# AI Voice

A macOS menubar app for voice-to-text transcription. Record audio with a global hotkey, transcribe via OpenAI Whisper, and auto-paste the result into your active application.

## Features

- Push-to-talk global hotkey (configurable)
- Transcription via OpenAI Whisper API
- Auto-paste into active app after transcription
- Recording overlay with visual aura effect
- Status island indicator during recording
- Transcription history with playback
- Multi-language support (auto-detect, Ukrainian, English, Russian, etc.)
- Native macOS app — no Electron, no web views

## Requirements

- macOS 14.0 (Sonoma) or later
- Swift 5.9+
- An OpenAI API key (for Whisper transcription)

## Build & Install

```bash
bash build.sh
cp -r AI\ Voice.app ~/Applications/
open ~/Applications/AI\ Voice.app
```

## Setup

1. Get an OpenAI API key from [platform.openai.com](https://platform.openai.com/api-keys)
2. Launch the app — it appears in your menubar
3. Open Settings and paste your API key
4. Grant Accessibility and Microphone permissions when prompted

> Your API key is stored locally on your machine. It is never sent anywhere except OpenAI's transcription endpoint.

## Tests

```bash
swift test
```

## License

[MIT](LICENSE)
