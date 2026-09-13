# Local transaction race backport

Base: cloud_firestore_platform_interface 6.6.12 (pub.dev), original BSD license retained.
Only `lib/src/method_channel/method_channel_firestore.dart` differs from upstream.
The app uses a path override, so CI/build machines receive the same fix without editing a global pub cache.

`runTransaction` now settles errors only once, checks completion after awaited native calls, and reports stream/store failures through the returned Future. It does not swallow transaction failures or retry failed business validations as successful writes.

Upstream issue: https://github.com/firebase/flutterfire/issues/18551

Regression test: `flutter test test/firestore_transaction_race_test.dart`. It sends a native error while the failing Dart callback awaits native cleanup, then releases cleanup. The original error must be delivered without an uncaught double-completion error.

Remove the override and this backport only when upgrading to a compatible official release verified against the same race test. No Firebase native SDK versions were changed.
