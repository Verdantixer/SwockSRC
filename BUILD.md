# Build guide

## Prerequisites

- Flutter SDK 3.47+
- Android SDK 36 or compatible version
- JDK 17
- Android command-line tools

## Setup

```bash
export PATH="/home/richboybrown/flutter-sdk/bin:$PATH"
flutter doctor
```

If Android SDK components are missing, install the Android platform and build tools with Android Studio or the SDK manager.

## Run the project

```bash
cd /home/richboybrown/Downloads/swock
flutter pub get
flutter run
```

## Build APK

```bash
flutter build apk --debug
# or
flutter build apk --release
```

## Notes

- The Android project is configured for the `com.swock.vpn.swock` package namespace.
- The app is Android-only and follows the real `VpnService` design model.
- The Swock Android client and Go server support raw TCP, WebSocket, TLS, and WebSocket-over-TLS (WSS) transports for the SWK1 tunnel protocol.
- Enable server-side TLS by providing both `-tls-cert /path/to/fullchain.pem` and `-tls-key /path/to/private.key` to `swock-server`. Android validates the certificate chain and SNI; do not use a self-signed certificate in production.
- WebSocket profiles use the configured path and optional Host header. Both client and server must point to an endpoint that forwards WebSocket upgrades to the Swock server.
- The Auto/TCP transport choice is independent from the TLS and WebSocket switches; either or both switches can be enabled.
