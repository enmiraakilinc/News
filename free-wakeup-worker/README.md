# Optional wakeup backend (free-tier design)

No user may trigger an alarm until the recipient explicitly enables that
conversation on that device. The receiver rechecks current account, membership,
consent and notification permission online before playing. A visible stop
notification is mandatory; no hidden alarm or lockscreen bypass is used.

Source: Worker HTTP handler (Workers Free).
Only authenticated Firebase users in an existing two-person conversation can
send, with recipient/device consent. The pending 1.14.16 version removes the
five-minute cooldown. FCM TTL is 60 seconds; late delivery is rejected by the receiver.
The receiver deduplicates event IDs without delaying new requests. Message/photo/audio contents
are neither passed to this API nor recorded by it. The dedicated Google service
account can read Firestore and send FCM; it cannot edit Firestore or IAM.

Before production activation:

1. Run `python setup_free_wakeup.py` for the concrete IAM review (no changes).
2. With explicit production approval, run `python setup_free_wakeup.py --apply`.
   The new dedicated credential is piped to Cloudflare secret storage. Never put
   the existing admin key, a private key, or a Firebase ID token in application
   code, public releases, TOML vars, logs or chat.
3. Deploy `npx wrangler@4 deploy`. No paid plan or paid binding is required.
4. Verify `/health`, unauthorized and disabled-consent responses before setting
   Firestore `config/wakeup` to `{enabled: true, endpoint: "https://...workers.dev"}`.
5. Apply the compiled owner-only settings/preview/audio rules with approval.
6. Validate on a real phone with recipient permission off/on, lockscreen,
   background, volume, notification/channel disabled, Stop, account switch,
   offline/delayed delivery and duplicate delivery. Android force-stop, DND,
   connectivity and battery limits may prevent delivery; do not promise a
   guaranteed alarm clock or an invisible incoming notification.

The application deliberately does not implement a launcher-only badge without
a notification: standard Android badges depend on an active notification.
This Worker does not relay voice/video. The separate 1.14.16 voice-call prototype
uses temporary Firestore signaling and direct WebRTC while both apps are open.
No TURN relay or background-call delivery is configured.
