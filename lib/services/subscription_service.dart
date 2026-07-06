import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ad_service.dart';
import 'auth_service.dart';

class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();

  static final instance = SubscriptionService._();

  static const entitlementId = 'premium';
  static const productId = 'stockstorage_premium_monthly';
  static const premiumDailyAiLimit = 5;
  static const androidApiKey = String.fromEnvironment('RC_ANDROID_API_KEY');
  static const iosApiKey = String.fromEnvironment('RC_IOS_API_KEY');

  StreamSubscription<User?>? _authSubscription;
  bool _configured = false;
  bool _isPremium = false;
  bool? _mirroredPremium; // user_public에 마지막으로 기록한 값 (중복 쓰기 방지)
  bool _loading = false;
  String? _error;
  String? _lastPurchaseError;
  Package? _monthlyPackage;

  bool get isConfigured => _configured;
  // 관리자 계정은 결제 없이도 프리미엄으로 취급(디버그/내부 검증용).
  bool get isPremium =>
      _isPremium ||
      AuthService.adminUids.contains(FirebaseAuth.instance.currentUser?.uid);
  bool get loading => _loading;
  String? get error => _error;
  String? get lastPurchaseError => _lastPurchaseError;
  Package? get monthlyPackage => _monthlyPackage;
  String get displayPrice =>
      _monthlyPackage?.storeProduct.priceString ?? '월 15,000원';
  bool get _isAppleStore =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  String get _storeName => _isAppleStore ? 'App Store' : 'Google Play';

  Future<void> initialize() async {
    if (kIsWeb) return;
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    if (!(isAndroid || isIOS)) return;
    final apiKey = isAndroid ? androidApiKey : iosApiKey;
    if (apiKey.isEmpty) {
      _error =
          'RevenueCat ${_isAppleStore ? 'iOS' : 'Android'} Public SDK key가 필요합니다.';
      notifyListeners();
      return;
    }

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      final config = PurchasesConfiguration(apiKey)
        ..appUserID = FirebaseAuth.instance.currentUser?.uid
        ..entitlementVerificationMode =
            EntitlementVerificationMode.informational;
      await Purchases.configure(config);
      Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
      _configured = true;
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
        _syncUser,
      );
      await refresh();
    } catch (e) {
      _error = '$_storeName 결제 연결을 준비하지 못했어요.';
      debugPrint('[SubscriptionService] configure failed: $e');
      notifyListeners();
    }
  }

  Future<void> _syncUser(User? user) async {
    if (!_configured) return;
    _mirroredPremium = null; // 계정 전환 시 재미러링 허용
    try {
      final info = user == null
          ? await Purchases.logOut()
          : (await Purchases.logIn(user.uid)).customerInfo;
      _applyCustomerInfo(info);
      await loadOffering();
    } catch (e) {
      debugPrint('[SubscriptionService] auth sync failed: $e');
      await refresh();
    }
  }

  Future<void> refresh() async {
    if (!_configured) return;
    try {
      _applyCustomerInfo(await Purchases.getCustomerInfo());
      await loadOffering();
    } catch (e) {
      _error = '구독 정보를 불러오지 못했어요.';
      debugPrint('[SubscriptionService] refresh failed: $e');
      notifyListeners();
    }
  }

  Future<void> loadOffering() async {
    if (!_configured) return;
    try {
      final offering = (await Purchases.getOfferings()).current;
      _monthlyPackage =
          offering?.monthly ??
          offering?.availablePackages
              .where((item) => item.storeProduct.identifier == productId)
              .firstOrNull;
      _error = _monthlyPackage == null ? '스토어 상품을 준비 중입니다.' : null;
    } catch (e) {
      _error = '스토어 상품을 불러오지 못했어요.';
      debugPrint('[SubscriptionService] offering load failed: $e');
    }
    notifyListeners();
  }

  Future<bool> purchaseMonthly() async {
    final package = _monthlyPackage;
    if (!_configured || package == null) {
      _lastPurchaseError = '스토어 상품을 아직 불러오지 못했어요.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    try {
      _lastPurchaseError = null;
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _applyCustomerInfo(result.customerInfo);
      return _isPremium;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        _lastPurchaseError = '결제가 취소되었습니다.';
      } else {
        _lastPurchaseError = _purchaseErrorMessage(code, e);
        debugPrint(
          '[SubscriptionService] purchase failed: '
          'code=$code platformCode=${e.code} message=${e.message} details=${e.details}',
        );
      }
      notifyListeners();
      return false;
    } catch (e) {
      _lastPurchaseError = '결제를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.';
      debugPrint('[SubscriptionService] purchase failed: $e');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> restore() async {
    if (!_configured) return false;
    _setLoading(true);
    try {
      _applyCustomerInfo(await Purchases.restorePurchases());
      return _isPremium;
    } catch (e) {
      _lastPurchaseError = '구매 복원을 완료하지 못했어요.';
      debugPrint('[SubscriptionService] restore failed: $e');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> openManageSubscription() async {
    final uri = defaultTargetPlatform == TargetPlatform.android
        ? Uri.parse(
            'https://play.google.com/store/account/subscriptions'
            '?sku=$productId&package=www.stockstorage.stockdiary',
          )
        : Uri.parse('https://apps.apple.com/account/subscriptions');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _applyCustomerInfo(CustomerInfo info) {
    final next = info.entitlements.active.containsKey(entitlementId);
    // 구독 변동(만료 포함)을 공개 프로필에 반영해 다른 유저 아바타 왕관과 동기화.
    _mirrorPremiumToPublic(next);
    AdService.setPremium(next);
    if (_isPremium == next) return;
    _isPremium = next;
    notifyListeners();
  }

  // 본인 프리미엄 여부를 user_public/{uid}.isPremium 으로 미러링.
  void _mirrorPremiumToPublic(bool value) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_mirroredPremium == value) return;
    _mirroredPremium = value;
    FirebaseFirestore.instance
        .collection('user_public')
        .doc(uid)
        .set({'isPremium': value}, SetOptions(merge: true))
        .catchError((_) => _mirroredPremium = null);
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }

  String _purchaseErrorMessage(PurchasesErrorCode code, PlatformException e) {
    final detail = _compactPurchaseErrorDetail(e);
    final base = switch (code) {
      PurchasesErrorCode.productNotAvailableForPurchaseError =>
        '구독 상품이 현재 구매 가능한 상태가 아니에요. $_storeName 상품 설정을 확인해 주세요.',
      PurchasesErrorCode.purchaseNotAllowedError =>
        '이 $_storeName 계정에서는 결제가 허용되지 않았어요.',
      PurchasesErrorCode.purchaseInvalidError ||
      PurchasesErrorCode.storeProblemError =>
        '$_storeName 결제가 완료되지 않았어요. 테스트 계정과 결제 상태를 확인해 주세요.',
      PurchasesErrorCode.paymentPendingError =>
        '결제가 대기 중입니다. $_storeName에서 결제 상태가 확정되면 자동 반영됩니다.',
      PurchasesErrorCode.productAlreadyPurchasedError =>
        '이미 구매한 구독이 있어요. 구매 복원을 눌러 상태를 갱신해 주세요.',
      PurchasesErrorCode.networkError ||
      PurchasesErrorCode.offlineConnectionError => '네트워크 연결 문제로 결제를 확인하지 못했어요.',
      PurchasesErrorCode.configurationError ||
      PurchasesErrorCode.invalidCredentialsError =>
        '구독 설정을 확인해야 합니다. RevenueCat/$_storeName 연결 상태를 점검해 주세요.',
      _ => '결제를 완료하지 못했어요. $_storeName 결제 상태를 확인해 주세요.',
    };
    return '$base (${code.name}${detail == null ? '' : ': $detail'})';
  }

  String? _compactPurchaseErrorDetail(PlatformException e) {
    final raw = [e.message, if (e.details != null) e.details.toString()]
        .whereType<String>()
        .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((value) => value.isNotEmpty)
        .join(' / ');
    if (raw.isEmpty) return null;
    return raw.length <= 120 ? raw : '${raw.substring(0, 120)}...';
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    if (_configured) {
      Purchases.removeCustomerInfoUpdateListener(_applyCustomerInfo);
    }
    super.dispose();
  }
}
