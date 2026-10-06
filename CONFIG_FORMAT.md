# Configuration format

The app stores profiles in a JSON format compatible with a simple import/export pipeline.

## Example

```json
{
  "version": 1,
  "profile": {
    "name": "My Server",
    "protocol": "shadowsocks",
    "server": "example.com",
    "port": 443,
    "password": "PASSWORD",
    "cipher": "aes-256-gcm",
    "transport": "tcp",
    "tls": {
      "enabled": true,
      "sni": "example.com"
    },
    "webSocket": {
      "enabled": true,
      "path": "/vpn",
      "host": "example.com"
    }
  }
}
```

## Validation rules

Imported configurations must be checked before being applied:

- `server` is required
- `port` must be a valid integer between 1 and 65535
- `protocol` must be supported
- `transport` must be supported
- TLS and WebSocket are independent layers; enabling both uses WebSocket over TLS (WSS)
- TLS certificates must be valid for the configured SNI and trusted by Android
- JSON must parse correctly
- malformed or missing values must produce a clear error

## Security note

Protected configuration files may encrypt the sensitive section with authenticated encryption. The app must never store export passwords in plain text.
