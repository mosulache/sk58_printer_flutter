# SK58 Printer Flutter App

A cross-platform Flutter application for printing QR code labels and custom text on Sinmark SK58 (or compatible) Bluetooth thermal printers.

## Features

- Scan and connect to Bluetooth SK58 printers (and compatible models)
- Print QR codes and custom text labels
- Automatic image resizing and ESC/POS command generation
- User-friendly interface for Android (and potentially other platforms)
- Real-time status and error feedback

## Screenshots

*(TBD not worthy now)*

## Getting Started

### Prerequisites
- Flutter SDK (latest stable)
- A Sinmark SK58 or compatible Bluetooth thermal printer
- Android device (tested), or other platforms supported by Flutter

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/sk58-printer.git
   cd sk58-printer
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## Usage

1. Make sure your SK58 printer is powered on and Bluetooth is enabled on your device.
2. Enter the text/number you want to print (this will also be encoded as a QR code).
3. Scan for Bluetooth devices and select your printer from the list.
4. Once connected, press "Print Label". The app will generate a QR code and send it (with your text) to the printer.

## Tech Stack
- Flutter
- flutter_blue_plus (Bluetooth communication)
- esc_pos_utils_plus (ESC/POS command generation)
- qr_flutter (QR code generation)
- image (image processing)
- permission_handler (runtime permissions)

## Troubleshooting
- Make sure you grant all Bluetooth and location permissions on Android.
- If the printer is not found, ensure it is powered on and not paired with another device.
- For best results, use the app on Android 8.0+.

## License
TBD

## Current Limitations
- Bluetooth printing is only tested and supported on Android devices.
- Bluetooth functionality does NOT work on Linux with the current implementation.
- Other platforms (iOS, Windows, macOS, Linux) are untested and may not work at all.

---

*Made with love and attitude. If you have issues, open one on GitHub, but don't whine*

Developed with the help of Danutza. Real friends know who she is.

