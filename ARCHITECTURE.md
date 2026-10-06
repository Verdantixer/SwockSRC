# Architecture

## Overview

The application follows a layered architecture designed for production quality and clean separation of concerns:

1. Flutter UI layer
2. App services and repositories
3. Typed profile and configuration models
4. Kotlin native VPN bridge
5. Android `VpnService`
6. Network engine abstraction for Shadowsocks and transports

## Dart layer

The Dart side owns:

- App shell and Material 3 theme
- Profile and transport configuration models
- Persistence and import/export logic
- Clipboard and settings handling
- UI and navigation

It intentionally does not implement actual VPN traffic routing. Instead, it communicates with the native Android layer via `MethodChannel` and `EventChannel`.

## Kotlin layer

The Android layer owns:

- Permission handling
- Foreground service lifecycle
- VpnService setup and shutdown
- Statistics and network state reporting
- Connection orchestration for the real engine

The main integration entry points are:

- `MyVpnService.kt`
- `VpnController.kt`
- `FlutterVpnBridge.kt`

## Networking engine abstraction

The engine boundary is intentionally isolated:

- `VpnEngine`: general VPN lifecycle API
- `TransportEngine`: transport-level connection contract
- `ShadowsocksEngine`: live Swock tunnel implementation

This keeps the Android VPN lifecycle and the live Swock transport independently
maintainable without changing the Flutter interface.

## Bridge API

The Flutter app calls into Android via method names such as:

- `connect`
- `disconnect`
- `getStatus`
- `getStatistics`
- `testConnection`
- `getNetworkInfo`

The native service can emit events including:

- `connectionStateChanged`
- `downloadSpeedChanged`
- `uploadSpeedChanged`
- `latencyChanged`
- `vpnError`
- `logMessage`

## Typical flow

1. User selects a profile in Flutter.
2. Flutter serializes the profile to JSON.
3. Dart invokes native method channel.
4. Kotlin `VpnController` dispatches to the engine.
5. The engine prepares the tunnel or socket and reports the resulting status back to Dart.
6. UI updates from the event stream.

## Security boundaries

- Secrets remain in secure storage or encrypted profile files.
- Logs and error messages never print plaintext credentials.
- Imports are validated before being accepted.
- Transport logic is isolated from UI code.
