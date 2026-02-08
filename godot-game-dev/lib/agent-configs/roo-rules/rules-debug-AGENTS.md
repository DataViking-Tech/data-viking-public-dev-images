# Project Debug Rules (Non-Obvious Only)
- DEBUG_LOGS flags are commonly exported in multiple scripts; keep them false by default and enable only when troubleshooting to avoid log spam.
- Server-only or authority-gated code can fail silently when running as a non-authoritative peer; confirm `multiplayer.is_server()` and offline-peer guards when actions appear to do nothing.
