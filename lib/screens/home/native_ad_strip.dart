import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/ad_service.dart';

class NativeAdStrip extends StatefulWidget {
  const NativeAdStrip({super.key});

  @override
  State<NativeAdStrip> createState() => _NativeAdStripState();
}

class _NativeAdStripState extends State<NativeAdStrip> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _prepareAd();
  }

  Future<void> _prepareAd() async {
    final ads = AdService.instance;
    await ads.initialize();
    if (!mounted || !ads.canRequestAds || ads.hasTemporaryAdFreeAccess) return;
    final ad = NativeAd(
      adUnitId: AdService.nativeId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: const Color(0xFF101512),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFE2E8E4),
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFA7B0AA),
          size: 12,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF07120B),
          backgroundColor: const Color(0xFF55E89A),
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    if (!mounted) {
      ad.dispose();
      return;
    }
    setState(() => _ad = ad);
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: AdService.instance.adFreeAccess,
    builder: (context, adFree, _) {
    final ad = _ad;
    if (adFree || ad == null || !_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 5),
            child: Text(
              'AD',
              style: TextStyle(
                color: Color(0xFFA7B0AA),
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(height: 110, child: AdWidget(ad: ad)),
          ),
        ],
      ),
    );
    },
  );
}