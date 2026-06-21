import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ad_service.dart';

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
  bool _loading = false;
  String? _error;
  Package? _monthlyPackage;

  bool get isConfigured => _configured;
  bool get isPremium => _isPremium;
  bool get loading => _loading;
  String? get error => _error;
  Package? get monthlyPackage => _monthlyPackage;
  String get displayPrice =>
      _monthlyPackage?.storeProduct.priceString ?? '월 15,000원';

  Future<void> initialize() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final apiKey = Platform.isAndroid ? androidApiKey : iosApiKey;
    if (apiKey.isEmpty) return;

    try {
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
    } catch (_) {
      _error = '스토어 결제 연결을 준비 중입니다.';
      notifyListeners();
    }
  }

  Future<void> _syncUser(User? user) async {
    if (!_configured) return;
    try {
      final info = user == null
          ? await Purchases.logOut()
          : (await Purchases.logIn(user.uid)).customerInfo;
      _applyCustomerInfo(info);
      await loadOffering();
    } catch (_) {
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
    } catch (_) {
      _error = '스토어 상품을 불러오지 못했어요.';
    }
    notifyListeners();
  }

  Future<bool> purchaseMonthly() async {
    final package = _monthlyPackage;
    if (!_configured || package == null) return false;
    _setLoading(true);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _applyCustomerInfo(result.customerInfo);
      return _isPremium;
    } catch (_) {
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
    } catch (_) {
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> openManageSubscription() async {
    final uri = Platform.isAndroid
        ? Uri.parse(
            'https://play.google.com/store/account/subscriptions'
            '?sku=$productId&package=www.stockstorage.stockdiary',
          )
        : Uri.parse('https://apps.apple.com/account/subscriptions');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _applyCustomerInfo(CustomerInfo info) {
    final next = info.entitlements.active.containsKey(entitlementId);
    if (_isPremium == next) return;
    _isPremium = next;
    AdService.setPremium(next);
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
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
