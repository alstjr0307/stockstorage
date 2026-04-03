import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({
    super.key,
    required this.slotId,
  });

  final String slotId;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  static final Map<String, _BannerAdEntry> _adCache = <String, _BannerAdEntry>{};
  late final _BannerAdEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = _adCache.putIfAbsent(widget.slotId, () => _BannerAdEntry());
    _entry.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !AdService.adsEnabled) return const SizedBox.shrink();

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

  void ensureLoaded() {
    if (_loading || loaded.value || ad != null) return;
    _loading = true;
    final banner = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          loaded.value = true;
          _loading = false;
        },
        onAdFailedToLoad: (failedAd, _) {
          failedAd.dispose();
          ad = null;
          loaded.value = false;
          _loading = false;
        },
      ),
    );
    ad = banner;
    banner.load();
  }
}
