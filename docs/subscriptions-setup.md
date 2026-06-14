# 프리미엄 월간 구독 설정

앱 상품은 `stockstorage_premium_monthly`, RevenueCat entitlement는 `premium`으로
고정한다. 무료 사용자는 기존 광고 및 레벨별 AI 분석 한도를 그대로 사용한다.
프리미엄 사용자는 모든 광고가 제거되고 AI 종목 분석을 하루 3회 광고 없이 사용할
수 있다.

## Google Play Console

1. `수익 창출 > 제품 > 정기 결제`에서 `stockstorage_premium_monthly` 구독을 만든다.
2. 자동 갱신 base plan `monthly`를 만들고 결제 기간을 1개월로 설정한다.
3. 대한민국 가격을 `23,000원`으로 설정하고 base plan을 활성화한다.
4. 라이선스 테스터와 내부 테스트 트랙에서 테스트 계정을 등록한다.

## App Store Connect

1. `Monetization > Subscriptions`에서 `StockStorage Premium` 구독 그룹을 만든다.
2. 그룹 안에 `stockstorage_premium_monthly` 자동 갱신 구독을 만든다.
3. 구독 기간을 1개월로 설정하고 대한민국 가격을 `23,000원`으로 설정한다.
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
클라이언트용 키이며 RevenueCat Secret API key와 다르다.

```powershell
flutter build appbundle --release `
  --dart-define=RC_ANDROID_API_KEY=goog_xxx

flutter build ipa --release `
  --dart-define=RC_IOS_API_KEY=appl_xxx
```

## 출시 전 확인

1. 무료 계정에서 기존 배너, 전면, 보상형 광고와 레벨별 AI 한도가 유지되는지 확인한다.
2. Android 내부 테스트 결제 후 모든 광고가 즉시 사라지는지 확인한다.
3. iOS Sandbox 결제 후 모든 광고가 즉시 사라지는지 확인한다.
4. 프리미엄 계정에서 AI 분석 3회까지 광고 없이 실행되고 4회째 차단되는지 확인한다.
5. 구매 복원과 스토어 구독 관리 버튼을 양쪽 플랫폼에서 확인한다.
6. 해지, 만료, 환불 후 무료 상태로 돌아오는지 확인한다.
