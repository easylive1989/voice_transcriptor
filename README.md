# Voice Transcriptor

A macOS intelligent voice note tool that allows you to transcribe microphone or system audio to Traditional Chinese text using local AI (Whisper).

## Features

- **Press & Hold to Record**:
  - Key `F1` (default): Record Microphone.
  - Key `F2` (default): Record System Audio.
  - *Note: Default keys changed to F1/F2 to avoid interfering with typing. You can change them in Settings.*
- **Local AI Transcription**: Uses `whisper.cpp` locally (no cloud API).
- **Format**: Optimized for Traditional Chinese output.
- **Copy to Clipboard**: Automatically copies transcribed text to clipboard.

## Requirements

- macOS 14.0+ (Sonoma) or later.
- Xcode 15+ (for building).

## Setup & Build

1. **Clone the repository**:
   ```bash
   git clone <repository_url>
   cd VoiceTranscriptor
   ```

2. **Download Whisper Model**:
   You need to download a model file compatible with `whisper.cpp` (ggml format).

   - Recommended: `ggml-base.bin` or `ggml-small.bin`.
   - Download from: [Hugging Face - ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp/tree/main)

   Place the `.bin` file in the root directory of the project or anywhere you like (you can select it in the app settings later).

3. **Build and Run**:

   **Option A: Xcode (Recommended)**
   1. Open the folder in Xcode.
   2. Ensure the `Info.plist` is handled or manually add the keys (Permissions) to the project settings if Xcode generates one.
   3. Build and Run.

   **Option B: Command Line**
   ```bash
   swift run
   ```

   **Important regarding Info.plist**:
   This project is a Swift Package Executable. To run it as a proper macOS app with permissions, you should generate an Xcode project:
   ```bash
   swift package generate-xcodeproj
   ```
   Then configure the target to use the provided `Info.plist` or add `NSMicrophoneUsageDescription` and `LSUIElement` (for menu bar app) manually in the Build Settings/Info tab.

   *Note: You might need to sign the app to grant Accessibility and Screen Recording permissions.*

## Permissions

When you run the app for the first time:

1. **Accessibility**: Required to detect global key presses (Press & Hold). Go to `System Settings > Privacy & Security > Accessibility` and add the app/terminal.
2. **Screen Recording**: Required for system audio recording. Go to `System Settings > Privacy & Security > Screen Recording`.
3. **Microphone**: Required for voice recording.

## Usage

1. Launch the app. A waveform icon will appear in the menu bar.
2. Go to `Settings` via the menu bar icon to load your model file (`ggml-base.bin`) if not found automatically.
3. Hold `X` to speak. Release to transcribe.
4. Hold `Y` to capture system audio. Release to transcribe.
5. Paste the text anywhere (`Cmd + V`).

## Troubleshooting

- **Audio not recording?** Check System Settings for Microphone/Screen Recording permissions.
- **Whisper error?** Ensure you selected a valid `ggml` model file.
- **Key presses not working?** Ensure Accessibility permission is granted.
