# Clipist

A native macOS menu bar application that captures selected text from any application and instantly sends it as a task to Todoist using a global keyboard shortcut.

## Features

- **Global Hotkey**: Press Cmd+Shift+Y anywhere on macOS to capture selected text
- **Seamless Integration**: Works with any application that supports text selection
- **Menu Bar App**: Runs discreetly without a Dock icon
- **Secure Storage**: API tokens stored in macOS Keychain
- **Non-Destructive**: Preserves your clipboard content after capture
- **Native Notifications**: Confirms when tasks are successfully created

## Getting Started

### Prerequisites

- macOS 11.0 or later
- A Todoist account
- Xcode 14.0 or later (for development)

### Installation for Users

1. Download the latest release from the Releases page
2. Move Clipist.app to your Applications folder
3. Launch Clipist from Applications
4. Grant required permissions when prompted:
   - **Accessibility**: Required to read selected text
   - **Input Monitoring**: Required for global hotkey to function
   - **Notifications**: Optional, for task creation confirmations

### Configuration

1. Click the Clipist icon in the menu bar
2. Select "Open Preferences"
3. Enter your Todoist API token
   - Get your token from: Todoist Settings > Integrations > Developer
4. Close the preferences window

### Usage

1. Select any text in any application
2. Press Cmd+Shift+Y
3. A notification confirms the task was added to your Todoist inbox

## Development

### Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/Clipist.git
cd Clipist

# Open in Xcode
open Clipist.xcodeproj

# Build and run
# In Xcode: Product > Run (Cmd+R)
```

### Running Tests

#### Using Xcode

1. Open Clipist.xcodeproj in Xcode
2. Press Cmd+U to run all tests
3. View results in the Test Navigator (Cmd+6)

#### Using Command Line

```bash
# Run all tests
xcodebuild test -project Clipist.xcodeproj -scheme Clipist -destination 'platform=macOS'

# Run tests with coverage
xcodebuild test -project Clipist.xcodeproj -scheme Clipist -destination 'platform=macOS' -enableCodeCoverage YES
```

### Project Structure

```
Clipist/
├── Clipist/
│   ├── ClipistApp.swift      # Main application logic
│   └── KeychainHelper.swift  # Secure token storage
├── ClipistTests/             # Unit tests
└── ClipistUITests/           # UI tests
```

### Key Components

- **ClipistApp.swift** contains the entire application in a single file:
  - `AppDelegate`: Application lifecycle, hotkey registration, text capture
  - `ContentView`: Preferences interface
  - `PermissionGuideView`: Step-by-step permission setup
  - `EventMonitor`: Global event handling for popover dismissal

- **KeychainHelper.swift**: Wrapper for macOS Keychain to securely store the Todoist API token

### Architecture Notes

**Text Capture Flow:**
1. User presses Cmd+Shift+Y
2. App records current clipboard state (using changeCount)
3. Simulates Cmd+C using CGEvent API
4. Waits for clipboard change via changeCount polling
5. Reads captured text
6. Restores original clipboard with safeguards

**Hotkey Registration:**
- Uses Carbon Events API (RegisterEventHotKey)
- Registers Cmd+Shift+Y (key code 0x10)
- Posts notification when pressed, handled by handleHotKey

**Permission Requirements:**
- Accessibility: Required to simulate keystrokes and read clipboard
- Input Monitoring: Required for global hotkey functionality
- Notifications: Optional, for user feedback

## Troubleshooting

**Hotkey not working:**
- Check Input Monitoring permission in System Settings > Privacy & Security > Input Monitoring
- Ensure no other app is using Cmd+Shift+Y

**Text not capturing:**
- Verify Accessibility permission is granted
- Try restarting the app after granting permissions

**Tasks not appearing in Todoist:**
- Verify your API token is correct
- Check your internet connection
- Look for error notifications

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with SwiftUI and AppKit
- Uses the Todoist REST API v2
