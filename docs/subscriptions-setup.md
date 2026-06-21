# 프리미엄 월간 구독 설정

앱 상품은 `stockstorage_premium_monthly`, RevenueCat entitlement는 `premium`으로
고정한다. 무료 사용자는 기존 광고 및 레벨별 AI 분석 한도를 그대로 사용한다.
프리미엄 사용자는 모든 광고가 제거되고 AI 종목 분석을 하루 5회 광고 없이 사용할
수 있다.

## Google Play Console

1. `수익 창출 > 제품 > 정기 결제`에서 `stockstorage_premium_monthly` 구독을 만든다.
2. 자동 갱신 base plan `monthly`를 만들고 결제 기간을 1개월로 설정한다.
3. 대한민국 가격을 `15,000원`으로 설정하고 base plan을 활성화한다.
4. 라이선스 테스터와 내부 테스트 트랙에서 테스트 계정을 등록한다.

## App Store Connect

1. `Monetization > Subscriptions`에서 `StockStorage Premium` 구독 그룹을 만든다.
2. 그룹 안에 `stockstorage_premium_monthly` 자동 갱신 구독을 만든다.
3. 구독 기간을 1개월로 설정하고 대한민국 가격을 `15,000원`으로 설정한다.
4. 한국어 표시 이름, 설명, 심사용 스크린샷을 등록한다.
5. Xcode Runner target의 `Signing & Capabilities`에서 `In-App Purchase`를 추가한다.
6. Sandbox 테스터를 등록한다.

## RevenueCat

RevenueCat은 App Store와 Google Play 영수증을 검증하고 갱신, 해지, 환불 상태를 한
곳에서 정리한다.

1. RevenueCat 프로젝트와 iOS, Android 앱을 만든다.
2. 양쪽 스토어의 `stockstorage_premium_monthly` 상품을 가져온다.
3. `premium` entitlement를 만들고 두 상품을 연결한다.
4. 기본 offering에 월간 package를 추가한다.
5. Firebase Functions에서 사용할 Secret API key를 등록한다.

```powershell
firebase functions:secrets:set REVENUECAT_SECRET_API_KEY
firebase deploy --only functions,firestore:rules
```

## 앱 빌드

RevenueCat의 Android와 iOS Public SDK key를 빌드 시 주입한다. Public SDK key는
클라이언트용 키이며 RevenueCat Secret API key와 다르다. 키를 빌드 명령에 직접
넣는 대신 `dart_defines.json`(git에 커밋하지 않음)에 보관하고
`--dart-define-from-file`로 주입한다.

1. `dart_defines.example.json`을 복사해 `dart_defines.json`을 만들고 실제 키를 채운다.
   - `RC_ANDROID_API_KEY`: RevenueCat Play Store 앱의 Public SDK key (`goog_…`)
   - `RC_IOS_API_KEY`: RevenueCat App Store 앱의 Public SDK key (`appl_…`)
2. 키가 비어 있으면 `SubscriptionService.initialize()`가 그대로 반환하므로 구독
   화면이 비활성 상태가 된다. 출시 빌드 전 반드시 채울 것.

```bash
# 로컬 실행
flutter run --dart-define-from-file=dart_defines.json

# 릴리즈 빌드
flutter build appbundle --release --dart-define-from-file=dart_defines.json
flutter build ipa --release --dart-define-from-file=dart_defines.json
```

## 출시 전 확인

1. 무료 계정에서 기존 배너, 전면, 보상형 광고와 레벨별 AI 한도가 유지되는지 확인한다.
2. Android 내부 테스트 결제 후 모든 광고가 즉시 사라지는지 확인한다.
3. iOS Sandbox 결제 후 모든 광고가 즉시 사라지는지 확인한다.
4. 프리미엄 계정에서 AI 분석 5회까지 광고 없이 실행되고 6회째 차단되는지 확인한다.
5. 구매 복원과 스토어 구독 관리 버튼을 양쪽 플랫폼에서 확인한다.
6. 해지, 만료, 환불 후 무료 상태로 돌아오는지 확인한다.
