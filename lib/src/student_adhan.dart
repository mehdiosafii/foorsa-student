/// The adhan at prayer times (the owner, 1 Nov 2026: "if applicant chooses adan, an adan real
/// life one, needs to play where ever it's time").
///
/// The portal computes the prayer times on the phone, where the student is (its
/// shared/prayerTimes.ts and shared/adhanSchedule.ts), and hands the next calls to the app with
/// `adhanSync` each time it opens; the app schedules one local notification per call with a real
/// recorded adhan as its sound, so it sounds with the app closed and the phone locked. The texts
/// come written in the student's language.
///
/// The sound is one freely licensed recording (Aaqib Azeez, Wikimedia Commons, CC BY-SA 4.0), cut
/// by the portal's scripts/adhan/make.py:
///  - iPhone: `assets/sounds/adhan/foorsa_adhan.caf`, the opening (26.8 s): iOS plays a
///    notification's sound only if it is under 30 seconds, and only from the app bundle or the app's
///    Library/Sounds folder, where it is copied before the first call is scheduled.
///  - Android: `res/raw/foorsa_adhan.ogg`, the whole call, on its own channel; Fajr on a second
///    channel with the opening (`foorsa_adhan_short.ogg`): no freely licensed Fajr adhan, with
///    "as-salatu khayrun min an-nawm", was found, so Fajr calls with the opening both adhans share.
///    A channel's sound cannot change once made: a new recording means new channel ids.
library;

import 'app_language.dart';

const adhanChannelId = 'foorsa_adhan_v1';
const adhanFajrChannelId = 'foorsa_adhan_fajr_v1';
const adhanIosSound = 'foorsa_adhan.caf';
const adhanIosSoundAsset = 'assets/sounds/adhan/foorsa_adhan.caf';
const adhanAndroidSound = 'foorsa_adhan';
const adhanAndroidFajrSound = 'foorsa_adhan_short';

/// Notification ids for the calls: their own block (the class reminders use 1900000000 on).
const adhanNotificationBase = 1910000000;

/// The most calls the app holds. An iPhone keeps an app's soonest 64 notifications, the class
/// reminders included; the portal sends six days (30 calls) and opening the app moves them on.
const adhanMaxCalls = 40;

/// How far ahead a call may be: anything later is a mistake, not a schedule.
const adhanHorizon = Duration(days: 15);

const adhanPrayers = {'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'};

const adhanChannelName = Words('Adhan', 'Adhan', 'الأذان');
const adhanChannelDescription = Words(
    'The adhan at the prayer times you chose in the app',
    'L’adhan aux heures de prière que vous avez choisies dans l’application',
    'الأذان في أوقات الصلاة التي اخترتها في التطبيق');
const adhanFajrChannelName =
    Words('Adhan at Fajr', 'Adhan du Fajr', 'أذان الفجر');

class AdhanCall {
  const AdhanCall({
    required this.at,
    required this.prayer,
    required this.full,
    required this.title,
    required this.body,
  });

  final DateTime at;
  final String prayer;

  /// The whole adhan (Android); false for the opening (Fajr).
  final bool full;
  final String title;
  final String body;
}

/// A text the portal wrote, kept to one short line with no control characters.
String? _line(Object? value, {int max = 120}) {
  if (value is! String) return null;
  final clean = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
  if (clean.isEmpty) return null;
  return clean.length > max ? clean.substring(0, max) : clean;
}

/// The calls the portal sent that can be scheduled: a known prayer, a time in the next fifteen
/// days, a sound and two lines of text. Soonest first, one per minute, at most [adhanMaxCalls].
List<AdhanCall> validAdhanCalls(List<dynamic> raw, DateTime now) {
  final seen = <int>{};
  final out = <AdhanCall>[];
  for (final item in raw.whereType<Map>()) {
    final at = DateTime.tryParse('${item['at']}');
    final prayer = item['prayer'];
    final sound = item['sound'];
    final title = _line(item['title']);
    final body = _line(item['body'], max: 200);
    if (at == null ||
        prayer is! String ||
        !adhanPrayers.contains(prayer) ||
        (sound != 'full' && sound != 'short') ||
        title == null ||
        body == null) {
      continue;
    }
    if (!at.isAfter(now) || at.isAfter(now.add(adhanHorizon))) continue;
    final minute = at.toUtc().millisecondsSinceEpoch ~/ 60000;
    if (!seen.add(minute)) continue;
    out.add(AdhanCall(
        at: at.toUtc(),
        prayer: prayer,
        // Fajr always calls with the opening, whatever was asked (see above).
        full: sound == 'full' && prayer != 'fajr',
        title: title,
        body: body));
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(adhanMaxCalls).toList();
}
