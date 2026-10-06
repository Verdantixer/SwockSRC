# Swock VPN

Swock is an Android-focused Flutter + Kotlin VPN client built around a clear separation between the UI, profile model, and the native Android VPN layer.

## Overview

This project is intentionally structured to support a real Android `VpnService` implementation and a separate networking engine abstraction. The UI is built in Dart with Material 3, while the Android layer is implemented in Kotlin. The native layer exposes a bridge to the Flutter app for actions such as connection, disconnection, status checks, and traffic statistics.

## Design goals

- Android-only Flutter UI with Material 3
- Kotlin `VpnService` foundation with native lifecycle handling
- Real Swock tunnel using X25519 authentication and ChaCha20-Poly1305 packet encryption
- Strong typing and explicit configuration models
- Export, import, profile management, and secure storage for sensitive data
- Clean separation between Flutter UI and native networking

## Folder structure

- `lib/` – Dart UI, models, services, and theme
- `android/app/src/main/kotlin/...` – Kotlin VPN service and native bridge layer

## Required permissions

Add the following permissions to the Android manifest when enabling the actual VPN service:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

For a true VPN service, the app must also ask the user to enable the VPN permission from Android and start the service with `VpnService.prepare(...)` before attaching the tunnel.

## Build

```bash
export PATH="/home/richboybrown/flutter-sdk/bin:$PATH"
cd /home/richboybrown/Downloads/swock
flutter pub get
flutter analyze
flutter build apk --debug
```

## Native tunnel

The networking engine is intentionally abstracted in the Kotlin layer:

- `android/app/src/main/kotlin/com/swock/vpn/swock/networking/VpnEngine.kt`
- `android/app/src/main/kotlin/com/swock/vpn/swock/networking/ShadowsocksEngine.kt`
- `android/app/src/main/kotlin/com/swock/vpn/swock/networking/TransportEngine.kt`

`ShadowsocksEngine` is the live Android tunnel implementation. It protects the
transport socket from the Android VPN route, authenticates the Swock server
public key, then forwards encrypted IP packets between Android's TUN interface
and the selected TCP, WebSocket, TLS, or WebSocket-over-TLS endpoint.

## Server-side setup

A real VPS should expose one of the supported transports:

- Swock over TCP
- Swock over WebSocket
- Swock over TLS
- Swock over WebSocket + TLS

Profiles are created by the web panel as `swock://` URIs and contain the actual
endpoint, server public key, client private key, transport flags, and expiry.

## Security

- Sensitive profile data should be stored in Android Keystore-backed secure storage where practical.
- Credentials and secrets are not logged.
- Import validation is required before accepting a profile.
- Protected export files should use authenticated encryption in a production build.
