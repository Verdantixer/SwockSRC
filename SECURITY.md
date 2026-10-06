# Security

## Goals

- Protect sensitive credentials and keys
- Never log plaintext passwords
- Validate incoming profile data and avoid unsafe import behavior
- Support protected export files with authenticated encryption

## Recommended protections

1. Use Android Keystore-backed secure storage for secret material where practical.
2. Keep export passwords out of plain-text preferences or logs.
3. Encrypt protected export payloads with a modern authenticated scheme such as AES-GCM with a derived key.
4. Validate imported JSON before accepting it into the profile store.
5. Never execute commands or scripts from imported configuration.

## Sensitive data handling

The application must never store or display secrets in logs or error messages. Any profile import/export pipeline must parse the JSON and read only the necessary fields while rejecting malformed or unsafe input.
