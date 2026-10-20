# 1.14.23 (2067) — publication approval pending

Public notes: Kararlılık iyileştirmeleri.

- A video up to 100 MiB is sent as one attachment and one chat message. The previous 20 MiB automatic video splitting path is no longer used. Oversized input is rejected before file bytes are read or uploaded; file-picker videos use the same path.
- Upload and internal download limits both accept 100 MiB video. Photo/audio remain 20 MiB, other files 80 MiB. Existing Firestore document chunking is only a storage transport detail; it does not produce separate video messages or re-encode the video.
- Pending Firestore rules increase video metadata size to 104857600 bytes and chunk count to 228, retaining exact chunk count, ownership, membership, readiness and two-day expiry checks. Other media limits and download consent are unchanged.
- Both phones must update to open videos larger than 20 MiB; older versions reject those locally. No free-plan upgrade, new service or longer retention added.
- Validation: 13 affected Flutter tests passed, including sparse 40 MiB/100 MiB single-file preservation and rejection at 100 MiB+1; 15 isolated Firestore rule tests passed; analyzer clean. Full 100 MiB transfer on a physical phone has not been tested.
- After approval: deploy `publish_video_rules_1_14_23.py --deploy`, publish verified ARM64 APK v1.14.23, then run `publish_app_version_1_14_23.py`. Artifact report: ../release-1.14.23-build-report.json.

Publication completed after user approval: 100 MiB video rules deployed and verified; public ARM64 APK hash and size match the build report; config/app_version 2067 / 1.14.23 published and verified. Worker unchanged.
