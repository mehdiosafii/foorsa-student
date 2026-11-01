# Student chat notifications

Use the existing Foorsa Firebase project (the project named by `FIREBASE_SERVICE_ACCOUNT`), with the student native apps registered under their actual bundle/package IDs. Student registrations are stored separately from staff devices. Do not create a second Firebase project or change an existing application ID to enable notifications.

## Required deployment configuration

1. In the existing Firebase project, register the iOS application `ma.foorsa.foorsaStudent` and the Android application `ma.foorsa` (reuse a matching registration if it already exists). Download each platform's configuration. Verify both project IDs match the sender's service account. Android's namespace `ma.foorsa.student` is not its application ID.
2. Enable Push Notifications for the iOS identifier in Apple Developer. Upload the team's APNs authentication key to this Firebase project's iOS messaging settings. Regenerate the App Store provisioning profile with the `aps-environment` entitlement. Debug uses development; release uses production.
3. The current public client registrations are checked in at `ios/Runner/GoogleService-Info.plist` and `android/app/google-services.json`. Both use `foorsa-d71c1` (sender `643586848398`). CI runs `scripts/verify_firebase_config.py` before building. These client files are public identifiers, not service-account credentials. Do not put service-account private keys in the app. The older `com.foorsa.app` registration is not the current Android application.
4. Apply `server/migrations/create-student-push.sql` to the Foorsa Reward database and Conversation OS migration `20261026200000_student_push.sql` to its database. Neither migration backfills old notifications. Deploy the portal backend/frontend and Conversation OS changes together.
5. Set a cryptographically random shared `STUDENT_PUSH_WEBHOOK_SECRET` (at least 32 characters) in both backend environments. Keep it out of browser variables and Git. Foorsa Reward also needs its existing `FIREBASE_SERVICE_ACCOUNT` with Firebase Cloud Messaging API access.
6. Set Conversation OS `STUDENT_PUSH_WEBHOOK_URL` to `https://home.foorsa.ma/api/internal/student-chat-push`, `STUDENT_PUSH_SOURCE=foorsa`, and configure its existing authenticated cron mechanism (`CRON_SECRET`). Ensure `/mfc/api/student-push/tick` runs every minute. A non-Vercel scheduler must call this route too.
7. Build and distribute an updated native app. A website-only deployment cannot add push to already installed builds that lack Firebase.

## Behavior and verification

How a phone registers, every reason it may not and where each is reported, the
iPhone's notification delegate and the TestFlight check of the push
entitlement: `docs/student-push.md` (1 Nov 2026, after no phone had registered).

A committed outbound app-channel message queues one event for the current student recipient. Inbound messages, notes, failed sends, parents and other organizations do not qualify. The sender attempts delivery after its response; the persisted cron queue retries failures with backoff. Already read/deleted messages and changed recipient links are discarded before retry. Events expire after one day and at most 12 claims. Claims use leases and `SKIP LOCKED`; device/event records prevent ordinary retries from notifying twice. A provider acceptance followed by a database failure can still duplicate delivery; APNs collapse IDs and Android tags reduce visible duplicates. This is at-least-once delivery, not an exactly-once promise.

The phone asks permission after student authentication. Token rotation and app foreground refresh update registration. Sign-out unregisters the device and deletes its FCM token. Tapping an alert opens only `/contact/chat`. Foreground chat suppresses the extra banner. Lock-screen text is generic and contains no student details or message content.

Before release, use dedicated test students on physical iOS and Android devices. Test permission granted/denied, foreground outside chat, open chat, background, terminated app, tap navigation, sign-out and account switch, token refresh/reinstall, attachments, duplicate sends and temporary sender failure. Confirm no alert for inbound messages or staff notes. Do not test by messaging real students. Simulator compilation does not prove APNs delivery.

## Operations and capacity

Alert on tick failures, disabled configuration, rising pending count/oldest pending age, dropped events and FCM errors. Never log tokens or message content. The fallback worker claims 20 events per invocation with five concurrent requests; direct sends use an event-specific claim. For a 50,000-concurrent-user target, measure actual message rate, FCM quota, database connections and queue drain time in staging. Run more authenticated worker invocations if measured backlog exceeds the latency target; leases support parallel workers. This implementation alone is not a 50,000-user capacity certification.

Schedule deletion of `student_push_deliveries` older than 30 days and `student_push_devices` inactive for more than 45 days. The Conversation OS worker prunes terminal queue entries after 30 days in bounded batches. Keep server secrets distinct between staging and production, with separate test-device registrations.

## Rollback

Disable the Conversation OS worker configuration and cron first; existing chat still works. Native builds without Firebase configuration continue opening the portal, but cannot receive notifications. Keep the additive tables until outstanding events have expired. Do not remove shared staff Firebase credentials.

## Android validation while Apple setup is deferred

The independent Android validation workflow runs analysis, tests and an ARM64
debug APK build. Download the `foorsa-android-device-test-<commit>` artifact from
the successful Actions run; it is kept for 14 days. Use a dedicated test device
and test student account: it connects to the production portal. This is not a
Google Play release and cannot update an app signed with a different key. Keep
the existing installed student app intact. Play release signing and physical
device delivery verification are required before broad distribution.

TestFlight 1.2.19 (49), 29 Oct 2026, is the first iOS build released with these
notifications and the adviser calls. The build carries the push entitlement;
delivery to an iPhone still needs the APNs key in Firebase (step 2) and, for
calls, the APNs settings in `docs/student-calls.md`.

