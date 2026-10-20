# 1.14.24 (2068) — awaiting publication approval

Public notes: Görünüm ve kararlılık iyileştirmeleri.

## Organization

- 64 Dart sources moved into app/core/feature folders with imports and tests migrated. Main entry file is small; installed WorkManager callback library/name remains present and delegates to the extracted runtime. Private-home, public entry, tools and full-image viewer are separate libraries. Original lib/test sources and old main saved under archive/refactor.
- 176 historical workspace files archived without deletion: APKs/reports under artifacts/releases, internal notes under docs/releases, old operations/rules under archive, credentials/user backups under ignored private. Old-to-new manifests retained. Editor and connector configs have no references to moved files.
- Active admin helpers use the new credential location. Generic release build/publish tools replace per-version script duplication; build reads pubspec, verifies ARM64/signature/version and stores outputs in artifacts/releases/<version>. Publisher verifies local/uploaded/public hash and updates config/app_version with a race check. No publication performed yet.

## App behavior

- Shared courses are available in the private home, restricted to the secret-word pair. Existing pair cipher encrypts folder titles and note content; code-chat membership grants no access. Existing production membership rules already cover the course path; no server deployment needed.
- Personal courses live in the news drawer, separated by authenticated account UID on this device. They are local, not synchronized across phones. Folders support selectable text/code/announcements and images; code copy preserves indentation/newlines. Images can be enlarged. Shared images use the existing fit-to-document preparation; personal image originals stay local. Course deletion removes notes/images; local note reminders are cancelled before deletion.
- News media-note records are preserved and gain stable IDs for reminders. Local reminders use Android exact AlarmManager with notification/full-screen/exact-alarm permission prompts, replace/cancel by stable UUID, restore future alarms after reboot/update and require no Firebase session or internet at firing. Public reminder preference is separate from private wake permissions.
- News notification and personal reminder controls appear only in the news drawer. Private notification list omits news; its alarm-only preset preserves public-news preference.
- Active Real Mode button uses the selected theme's container/on-container colors; selected Hide button remains yellow.
- Wake alarms request the protected full-screen alarm activity whenever Android permits; previous in-app full-screen opt-out removed in favor of a permission-access control. Alarm activity hides its status bar, shows time and Alarmı kapat; secure-screen flag retained. Native foreground-service notification is still mandatory; Android can show heads-up instead when unlocked or lacking full-screen access. No guarantee of invisible system notifications.

## Verification and limits

- 95 Flutter tests passed, including account-isolated local persistence, image cleanup, exact code copy, pair encryption, news/settings separation and reminder permission gating. 16 isolated Firestore-rule tests passed, including exclusion of code-chat contacts from courses. Flutter analyze clean.
- Android release/signature verification recorded in artifacts/releases/1.14.24/build-report.json after build. No physical S25 validation of full-screen/locked-screen alarms or inter-device course synchronization has been performed. Force stop/OS battery/permission restrictions still apply.
- No paid service, Worker, IAM, Firestore rule or existing data-retention change. Videos remain a single attachment up to 100 MiB with 48-hour expiry. Course images are separate persistent notes, not chat attachments.

After user approval: `python tools/releases/publish.py --version 1.14.24 --publish`. Only the APK and short generic public notes are published.

Final signed ARM64 build verified: 1.14.24 / 2068, 38.47 MB. Final course/reminder checks (5 tests) and analyzer passed after async-bootstrap adjustment. All source-move destinations and original source backup verified. Publication pending; live 1.14.23 unchanged.
