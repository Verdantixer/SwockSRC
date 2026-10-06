import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

    static const _productionAppOpenId =
      'ca-app-pub-4770403343644676/2635640224';
    static const _productionNativeId =
      'ca-app-pub-4770403343644676/8764925147';
    static const _productionRewardedInterstitialId =
      'ca-app-pub-4770403343644676/6107981379';
    static const _productionRewardedId =
      'ca-app-pub-4770403343644676/2328518468';
    static const _testAppOpenId = 'ca-app-pub-3940256099942544/9257395921';
    static const _testNativeId = 'ca-app-pub-3940256099942544/2247696110';
    static const _testRewardedInterstitialId =
      'ca-app-pub-3940256099942544/5354046379';
    static const _testRewardedId = 'ca-app-pub-3940256099942544/5224354917';

    static String get appOpenId => kReleaseMode
      ? _productionAppOpenId
      : _testAppOpenId;
    static String get nativeId => kReleaseMode
      ? _productionNativeId
      : _testNativeId;
    static String get rewardedInterstitialId => kReleaseMode
      ? _productionRewardedInterstitialId
      : _testRewardedInterstitialId;
    static String get rewardedId => kReleaseMode
      ? _productionRewardedId
      : _testRewardedId;

  Future<void>? _initialization;
  bool _canRequestAds = false;
  bool _appOpenLoading = false;
  bool _showingAppOpen = false;
  DateTime? _lastAppOpenShown;
  DateTime? _adFreeUntil;
  AppOpenAd? _appOpenAd;

  bool get canRequestAds => _canRequestAds;
  bool get hasTemporaryAdFreeAccess =>
      _adFreeUntil != null && DateTime.now().isBefore(_adFreeUntil!);

    Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    final completer = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
            await _enableAdsIfAllowed();
          } catch (_) {
            await _enableAdsIfAllowed();
          } finally {
            if (!completer.isCompleted) completer.complete();
          }
        },
        (_) async {
          await _enableAdsIfAllowed();
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      try {
        await _enableAdsIfAllowed();
      } catch (_) {
        _canRequestAds = false;
      }
    }
  }

  Future<void> _enableAdsIfAllowed() async {
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    if (!_canRequestAds) return;
    await MobileAds.instance.initialize();
    _loadAppOpenAd();
  }

  Future<void> showPrivacyOptions() async {
    await initialize();
    final requirement = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    if (requirement == PrivacyOptionsRequirementStatus.required) {
      await ConsentForm.showPrivacyOptionsForm((_) async {
        await _enableAdsIfAllowed();
      });
    }
  }

  void _loadAppOpenAd() {
    if (!_canRequestAds || _appOpenLoading || _appOpenAd != null) return;
    _appOpenLoading = true;
    AppOpenAd.load(
      adUnitId: appOpenId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenLoading = false;
          _appOpenAd = ad;
        },
        onAdFailedToLoad: (_) => _appOpenLoading = false,
      ),
    );
  }

  void showAppOpenIfReady({required bool appWasBackgrounded}) {
    if (!_canRequestAds ||
        !_appOpenAdIsEligible(appWasBackgrounded: appWasBackgrounded)) {
      _loadAppOpenAd();
      return;
    }
    final ad = _appOpenAd;
    if (ad == null) {
      _loadAppOpenAd();
      return;
    }
    _appOpenAd = null;
    _showingAppOpen = true;
    _lastAppOpenShown = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (shownAd) {
        _showingAppOpen = false;
        shownAd.dispose();
        _loadAppOpenAd();
      },
      onAdFailedToShowFullScreenContent: (shownAd, _) {
        _showingAppOpen = false;
        shownAd.dispose();
        _loadAppOpenAd();
      },
    );
    ad.show();
  }

  bool _appOpenAdIsEligible({required bool appWasBackgrounded}) =>
      appWasBackgrounded &&
      !_showingAppOpen &&
      !hasTemporaryAdFreeAccess &&
      (_lastAppOpenShown == null ||
          DateTime.now().difference(_lastAppOpenShown!) >
              const Duration(hours: 4));

  Future<bool> showReward({required bool interstitial}) async {
    await initialize();
    if (!_canRequestAds || hasTemporaryAdFreeAccess) return false;
    final completer = Completer<bool>();
    final unitId = interstitial ? rewardedInterstitialId : rewardedId;
    void finish(bool earned) {
      if (!completer.isCompleted) completer.complete(earned);
    }

    final callback = RewardedInterstitialAdLoadCallback(
      onAdLoaded: (ad) {
        var earned = false;
        ad.fullScreenContentCallback =
            FullScreenContentCallback<RewardedInterstitialAd>(
              onAdDismissedFullScreenContent: (shownAd) {
                shownAd.dispose();
                if (earned) {
                  _adFreeUntil = DateTime.now().add(
                    Duration(minutes: interstitial ? 15 : 30),
                  );
                }
                finish(earned);
              },
              onAdFailedToShowFullScreenContent: (shownAd, _) {
                shownAd.dispose();
                finish(false);
              },
            );
        ad.show(
          onUserEarnedReward: (_, __) => earned = true,
        );
      },
      onAdFailedToLoad: (_) => finish(false),
    );
    if (interstitial) {
      await RewardedInterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: callback,
      );
    } else {
      await RewardedAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            var earned = false;
            ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
              onAdDismissedFullScreenContent: (shownAd) {
                shownAd.dispose();
                if (earned) {
                  _adFreeUntil = DateTime.now().add(const Duration(minutes: 30));
                }
                finish(earned);
              },
              onAdFailedToShowFullScreenContent: (shownAd, _) {
                shownAd.dispose();
                finish(false);
              },
            );
            ad.show(onUserEarnedReward: (_, __) => earned = true);
          },
          onAdFailedToLoad: (_) => finish(false),
        ),
      );
    }
    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => false,
    );
  }
}