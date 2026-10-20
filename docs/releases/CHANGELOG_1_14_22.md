# 1.14.22 (2066) — awaiting publication approval

Public notes: Görünüm ve kararlılık iyileştirmeleri.

- Feature notification switches update after successful persistence even if native notification cancellation or FCM topic cleanup fails; platform work has bounded waits. Choices remain independent and survive reopening.
- Feature switches explain what they notify about. Enabling requests missing Android notification permission at point of use; denial offers direct notification settings. Full-screen incoming-call access is explained before opening its special access page. Personal wake opt-in offers to enable its general alarm gate explicitly, without changing other features.
- Delayed incoming-call pushes cannot announce another incoming call while a call is active. Ongoing-call foreground notification uses a new MIN-importance channel with no sound, badge or heads-up alert. Android-mandated foreground-service notification and privacy indicators are retained.
- Chat photo/video viewers offer gallery saving. The sender saves their own media directly; other members create a deterministic export request. Sender sees requests only inside the conversation, can inspect the attachment and approve/decline; requester explicitly saves after approval. No system notification, automatic gallery write or Worker push added. Requests expire with the original 48-hour media deadline and are cleaned when existing app cleanup runs. Approval governs supported in-app gallery export, not a DRM guarantee against modified clients that can already view content.
- Tested Firestore rules bind requests to real media, sender, requester and source membership. Only sender can decide, no requester self-approval or identity/source mutation. New rules are pending; deploy before publishing APK. Existing media read rules and older client compatibility remain unchanged.
- Composer keeps separate schedule, file and camera controls as requested; redundant video confirmation removed. Single media uses one preview with optional naming; multi-part video names stay separately editable. Photo thumbnails use a smaller chat footprint; originals unchanged.
- Remote video fills a larger full-width area (52% of screen height instead of 35%) using cover fit; small edge cropping is possible. Local preview reduced to 80x106 so it obscures less of the remote feed. Existing screen protection remains enabled.
- Turuncu theme added with #823F0C containers, bright orange accents and contrasting text. Daily-question contrast tests include the new theme.
- Daily-question card titles, answers, edit icons and empty hints select a contrasting foreground against each card background; Love and purple use white on dark cards. All theme container combinations tested for minimum 4.5:1 text contrast.
- Clock integration, alarm playback and native alarm UI are unchanged. No promise to remove Android's mandatory notification or indicators. No paid plan, dependency, Worker or IAM change.

Validation: 90 Flutter tests passed; 14 isolated Firestore rule tests passed; Flutter analysis clean before final packaging. Signed physical-device ARM64 APK checked by release script. Physical S25, inter-device approval/gallery permissions and platform notification appearance still need device validation. Artifact details: ../release-1.14.22-build-report.json.

Release sequence after approval: `python publish_download_rules_1_14_22.py --deploy`, publish verified ARM64 APK as GitHub v1.14.22 with generic public notes, then `python publish_app_version_1_14_22.py`. Do not publish internal notes or credentials.

Final requested UI revision: separate composer controls restored, remote video enlarged, Turuncu added. 31 affected Flutter tests passed and analyzer clean; signed ARM64 APK rebuilt and report updated. Publication still awaits approval.

Publication complete after user approval: sender-consent rules deployed and verified; public ARM64 APK SHA-256/size match the build report; config/app_version 2066 / 1.14.22 published and verified. No Worker or IAM changes.
