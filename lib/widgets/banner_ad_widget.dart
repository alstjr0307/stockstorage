import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

final Map<String, _BannerAdEntry> _bannerAdCache = <String, _BannerAdEntry>{};

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({
    super.key,
    required this.slotId,
    this.adUnitId,
    this.fallbackAdUnitId,
    this.useCache = true,
  });

  final String slotId;
  final String? adUnitId;
  final String? fallbackAdUnitId;
  final bool useCache;

  static void prewarm({
    required String slotId,
    String? adUnitId,
    String? fallbackAdUnitId,
  }) {
    if (kIsWeb || !AdService.adsEnabled || AdService.isAdmin) return;
    final unitId = adUnitId ?? AdService.bannerAdUnitId;
    final cacheKey = '$slotId::$unitId';
    final entry = _bannerAdCache.putIfAbsent(cacheKey, () => _BannerAdEntry());
    entry.ensureLoaded(
      unitId,
      slotId: slotId,
      fallbackAdUnitId: fallbackAdUnitId,
    );
  }

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  late final _BannerAdEntry _entry;
  late final String _cacheKey;
  late final String _unitId;

  @override
  void initState() {
    super.initState();
    _unitId = widget.adUnitId ?? AdService.bannerAdUnitId;
    _cacheKey = '${widget.slotId}::$_unitId';
    if (kDebugMode) {
      debugPrint('[BannerAd] init slot=${widget.slotId} unit=$_unitId');
    }
    _entry = widget.useCache
        ? _bannerAdCache.putIfAbsent(_cacheKey, () => _BannerAdEntry())
        : _BannerAdEntry();
    _entry.ensureLoaded(
      _unitId,
      slotId: widget.slotId,
      fallbackAdUnitId: widget.fallbackAdUnitId,
    );
  }

  @override
  void dispose() {
    if (!widget.useCache) {
      _entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !AdService.adsEnabled || AdService.isAdmin) {
      if (kDebugMode) {
        debugPrint(
          '[BannerAd] hidden slot=${widget.slotId} '
          'isWeb=$kIsWeb adsEnabled=${AdService.adsEnabled} isAdmin=${AdService.isAdmin}',
        );
      }
      return const SizedBox.shrink();
    }
    _entry.ensureLoaded(
      _unitId,
      slotId: widget.slotId,
      fallbackAdUnitId: widget.fallbackAdUnitId,
    );

    return SizedBox(
      height: AdSize.banner.height.toDouble(),
      child: ValueListenableBuilder<bool>(
        valueListenable: _entry.loaded,
        builder: (context, isLoaded, child) {
          if (!isLoaded || _entry.ad == null) {
            return const SizedBox.shrink();
          }
          return Center(
            child: SizedBox(
              width: _entry.ad!.size.width.toDouble(),
              height: _entry.ad!.size.height.toDouble(),
              child: AdWidget(ad: _entry.ad!),
            ),
          );
        },
      ),
    );
  }
}

class _BannerAdEntry {
  BannerAd? ad;
  final ValueNotifier<bool> loaded = ValueNotifier<bool>(false);
  bool _loading = false;
  DateTime? _loadingSince;
  String? _adUnitId;
  bool _triedFallback = false;

  void ensureLoaded(
    String adUnitId, {
    String? slotId,
    String? fallbackAdUnitId,
  }) {
    if (_adUnitId != adUnitId) {
      _triedFallback = false;
    }
    _adUnitId = adUnitId;
    if (_loading) {
      final since = _loadingSince;
      if (since != null &&
          DateTime.now().difference(since) > const Duration(seconds: 8)) {
        if (kDebugMode) {
          debugPrint(
            '[BannerAd] timeout-retry slot=${slotId ?? '-'} unit=$adUnitId',
          );
        }
        _loading = false;
        _loadingSince = null;
        ad?.dispose();
        ad = null;
      } else {
        return;
      }
    }
    if (loaded.value || ad != null) return;
    _loading = true;
    _loadingSince = DateTime.now();
    if (kDebugMode) {
      debugPrint('[BannerAd] request slot=${slotId ?? '-'} unit=$adUnitId');
    }
    final banner = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (kDebugMode) {
            debugPrint(
              '[BannerAd] loaded slot=${slotId ?? '-'} unit=$adUnitId',
            );
          }
          loaded.value = true;
          _loading = false;
          _loadingSince = null;
        },
        onAdFailedToLoad: (failedAd, error) {
          if (kDebugMode) {
            debugPrint(
              '[BannerAd] failed slot=${slotId ?? '-'} unit=$adUnitId '
              'code=${error.code} message=${error.message}',
            );
          }
          failedAd.dispose();
          ad = null;
          loaded.value = false;
          _loading = false;
          _loadingSince = null;
          final canFallback =
              !_triedFallback &&
              fallbackAdUnitId != null &&
              fallbackAdUnitId.isNotEmpty &&
              fallbackAdUnitId != adUnitId;
          if (canFallback) {
            _triedFallback = true;
            if (kDebugMode) {
              debugPrint(
                '[BannerAd] fallback slot=${slotId ?? '-'} '
                'from=$adUnitId to=$fallbackAdUnitId',
              );
            }
            ensureLoaded(
              fallbackAdUnitId,
              slotId: slotId,
              fallbackAdUnitId: null,
            );
            return;
          }
          final retryUnitId = _adUnitId;
          if (retryUnitId != null) {
            Future<void>.delayed(const Duration(seconds: 10), () {
              ensureLoaded(
                retryUnitId,
                slotId: slotId,
                fallbackAdUnitId: fallbackAdUnitId,
              );
            });
          }
        },
      ),
    );
    ad = banner;
    banner.load();
  }

  void dispose() {
    ad?.dispose();
    ad = null;
    loaded.value = false;
    _loading = false;
    _loadingSince = null;
    _adUnitId = null;
    _triedFallback = false;
  }
}
