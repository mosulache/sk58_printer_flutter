# SK58 Printer Flutter App

A cross-platform Flutter application for printing QR code labels and custom text on Sinmark SK58 (or compatible) Bluetooth thermal printers.

## Features

- Scan and connect to Bluetooth SK58 printers (and compatible models)
- Print QR codes and custom text labels
- Cross-platform support (Linux and Android)
- Real-time connection status and error feedback
- Clean, modern Material Design interface

## Screenshots

*(Coming soon)*

## Getting Started

### Prerequisites
- Flutter SDK (latest stable)
- A Sinmark SK58 or compatible Bluetooth thermal printer
- Linux or Android device
- Bluetooth LE support

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/sk58-printer-flutter.git
   cd sk58-printer-flutter
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

1. Ensure your SK58 printer is powered on and Bluetooth is enabled
2. Enter the text you want to print (this will be encoded as a QR code)
3. Tap "Scan Bluetooth Devices" and select your printer
4. Once connected, tap "Print Label" to generate and print your QR code label

## Tech Stack
- Flutter
- universal_ble (Bluetooth LE communication)
- qr_flutter (QR code generation)
- permission_handler (runtime permissions)

## Platform Support
- ✅ Android: Fully supported
- ✅ Linux: Supported (requires Bluetooth LE)
- ⚠️ Other platforms: Untested

## Troubleshooting
- Android: Grant all required Bluetooth and location permissions
- Linux: Ensure Bluetooth service is running (`bluetoothd`)
- General: Printer should be powered on and not connected to other devices

## License
MIT License

---

*Built with Flutter and attitude. Issues? Open one on GitHub, let's solve it together!*

