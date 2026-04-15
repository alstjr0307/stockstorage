# Google Play Console Integration Guide

This project is configured for Google Play upload with `Gradle Play Publisher`.

## 1) Create a Play Console service account
1. In Play Console, go to `Settings` -> `Developer account` -> `API access`.
2. Link a Google Cloud project.
3. Create a service account and download the JSON key file.
4. Grant app permissions to that service account in Play Console.
   - Minimum suggested role: `Release Manager`

## 2) Local publish
1. Put the JSON key at `android/play-service-account.json`.
2. Run:

```powershell
cd android
.\gradlew.bat publishReleaseBundle
```

Default track is `internal`.

### Publish to a different track
```powershell
cd android
.\gradlew.bat publishReleaseBundle -PPLAY_TRACK=production
```

Track examples: `internal`, `alpha`, `beta`, `production`

### Use a custom JSON path
```powershell
cd android
.\gradlew.bat publishReleaseBundle -PPLAY_SERVICE_ACCOUNT_JSON=C:\secure\play-key.json
```

## 3) Build AAB first (optional)
```powershell
flutter build appbundle --release
cd android
.\gradlew.bat publishReleaseBundle
```

## 4) Notes
- `applicationId` should match your Play Console package name: `www.stockstorage.stockdiary`.
- Upload keystore and Play App Signing key may be different keys.
- First release may still require manual Store Listing and policy setup in Play Console.
