# Incoming adviser voice calls

Status: implementation branch; production activation and physical-device validation pending.

Conversation OS alone initiates calls. The student web portal and native app can answer, decline, mute and end a call; the native app also exposes speaker routing. There is no student dialler, outgoing API action or missed-call callback. Audio is not recorded.

## Release dependencies

1. Apply `conversation-os/apps/console/supabase/migrations/20261028113751_student_voice_calls.sql` to the Conversation OS database after the existing student-chat migrations. Apply `foorsa-reward/server/migrations/add-student-call-devices.sql` to the portal database **before** deploying its new device-registration route.
2. Configure a production TURN relay in Conversation OS: `TURN_URLS`, `TURN_USERNAME`, `TURN_CREDENTIAL`. Use a dedicated managed relay with UDP and TLS/TCP connectivity. Public demo relay credentials are deliberately not used. Current integration accepts static credentials; use a scoped provider account, rotate credentials, and monitor quota. Calls cannot be advertised as reliable across networks until the relay is tested.
3. Set a random server-only `STUDENT_CALL_TOKEN_SECRET` of at least 32 characters in Conversation OS. It signs receive-only, single-call capabilities. Do not reuse the Supabase JWT signing key.
4. Set the same `STUDENT_PUSH_WEBHOOK_SECRET` in both servers, and set Conversation OS `STUDENT_PUSH_WEBHOOK_URL` to the portal's HTTPS `/api/internal/student-chat-push` endpoint. Existing message notifications use this same trusted server connection.
5. In the portal server, configure `STUDENT_APNS_KEY` (APNs-capable .p8 private key), `STUDENT_APNS_KEY_ID`, `STUDENT_APNS_TEAM_ID`, and `STUDENT_APNS_BUNDLE_ID=ma.foorsa.foorsaStudent`. This is an APNs key, not an App Store Connect API key. `STUDENT_APNS_SANDBOX=true` is only for development-provisioned devices; TestFlight uses production APNs. Existing `FIREBASE_SERVICE_ACCOUNT` must match Android's Firebase project.
6. Build and distribute a new signed iOS/Android app. iOS needs Push Notifications, VoIP and Audio background modes, and a profile with push entitlement. Android uses Telecom and incoming-call notifications. Full-screen access is controlled by Android/user settings; Play Console declarations must accurately describe this receive-only calling feature. A server deployment cannot update an installed binary.
7. Test with dedicated test accounts on physical iPhone and Android phones before setting `STUDENT_CALLS_ENABLED=true` in Conversation OS. Never use customer contacts as fixtures.

## Required device verification

- Incoming call with app foregrounded, backgrounded and normally terminated; lock-screen answer and decline.
- iOS CallKit audio activation; microphone denied/revoked; Bluetooth/headset, speaker and mute.
- Separate Wi-Fi/mobile networks, restrictive NAT and TURN/TLS; poor signal; loss of connectivity; interruption by a cellular call.
- Caller cancellation while phone is locked, no answer, duplicate push, answer on another logged-in device, logout/account switch, app crash and reopen.
- Confirm the student cannot originate calls via UI, system Recents, notifications or HTTP requests.
- DND, OS notification restrictions and explicit Android force-stop can suppress ringing. Do not promise delivery irrespective of OS/network state.

The server expires unanswered calls after 45 seconds, connecting calls after 45 seconds, and active calls after a 75-second missing heartbeat or two hours. Terminal calls erase SDP. Private chat rooms carry call invalidations only; SDP is fetched through checked endpoints. Native audio runs in Flutter WebRTC rather than the suspended web view. Native call capabilities never grant profile/chat access.

## Validation performed locally

- Conversation OS: 473 tests, TypeScript and production build.
- Disposable PostgreSQL: adviser-only initiation, cross-workspace and cross-student denial, first-device answer ownership, idempotent start, busy exclusion, private notifications and SDP cleanup.
- Portal: frontend/server builds; invite-validation and realtime-hook tests.
- Native: iOS simulator and Android debug builds; Flutter analysis and unit tests.
- Web UI: incoming-screen visual inspection and decline dismissal with local fake signaling.

These checks do not substitute for APNs/FCM delivery and two-party audio testing on real devices. No production migration or feature activation has been performed by this implementation branch.
