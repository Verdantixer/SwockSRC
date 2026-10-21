import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  static const _productionAppOpenId = 'ca-app-pub-4770403343644676/2635640224';
  static const _productionNativeId = 'ca-app-pub-4770403343644676/8764925147';
  static const _productionRewardedInterstitialId =
      'ca-app-pub-4770403343644676/6107981379';
  static const _productionRewardedId = 'ca-app-pub-4770403343644676/2328518468';
  static const _testAppOpenId = 'ca-app-pub-3940256099942544/9257395921';
  static const _testNativeId = 'ca-app-pub-3940256099942544/2247696110';
  static const _testRewardedInterstitialId =
      'ca-app-pub-3940256099942544/5354046379';
  static const _testRewardedId = 'ca-app-pub-3940256099942544/5224354917';
  static const _adFreeUntilKey = 'temporary_ad_free_until_ms';
  static const _lastRewardOfferKey = 'last_ad_free_offer_ms';

  static String get appOpenId =>
      kReleaseMode ? _productionAppOpenId : _testAppOpenId;
  static String get nativeId =>
      kReleaseMode ? _productionNativeId : _testNativeId;
  static String get rewardedInterstitialId =>
      kReleaseMode
          ? _productionRewardedInterstitialId
          : _testRewardedInterstitialId;
  static String get rewardedId =>
      kReleaseMode ? _productionRewardedId : _testRewardedId;

  Future<void>? _initialization;
  bool _canRequestAds = false;
  bool _appOpenLoading = false;
  bool _showingAppOpen = false;
  bool _showingReward = false;
  bool _timeRewardLoading = false;
  Timer? _adFreeExpiryTimer;
  bool _foregroundAdPending = false;
  DateTime? _lastAppOpenShown;
  DateTime? _lastRewardOfferShown;
  DateTime? _adFreeUntil;
  AppOpenAd? _appOpenAd;
  RewardedAd? _timeRewardAd;
  final ValueNotifier<bool> adFreeAccess = ValueNotifier(false);

  bool get canRequestAds => _canRequestAds;
  bool get hasTemporaryAdFreeAccess =>
      _adFreeUntil != null && DateTime.now().isBefore(_adFreeUntil!);
    bool get canOfferTemporaryAdFree =>
      _canRequestAds &&
      !hasTemporaryAdFreeAccess &&
      !_showingAppOpen &&
      !_showingReward &&
      (_lastRewardOfferShown == null ||
        DateTime.now().difference(_lastRewardOfferShown!) >=
          const Duration(minutes: 30));

  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    await _restoreRewardState();
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

  Future<void> _restoreRewardState() async {
    final prefs = await SharedPreferences.getInstance();
    final adFreeUntilMs = prefs.getInt(_adFreeUntilKey);
    final lastOfferMs = prefs.getInt(_lastRewardOfferKey);
    _adFreeUntil = adFreeUntilMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(adFreeUntilMs);
    _lastRewardOfferShown = lastOfferMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastOfferMs);
    adFreeAccess.value = hasTemporaryAdFreeAccess;
    if (_adFreeUntil != null && !hasTemporaryAdFreeAccess) {
      _adFreeUntil = null;
      await prefs.remove(_adFreeUntilKey);
    } else {
      _scheduleAdFreeExpiry();
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
    final requirement =
        await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
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
          if (_foregroundAdPending) {
            _foregroundAdPending = false;
            showAppOpenIfReady(appWasBackgrounded: true);
          }
        },
        onAdFailedToLoad: (_) => _appOpenLoading = false,
      ),
    );
  }

  void showAppOpenIfReady({required bool appWasBackgrounded}) {
    if (!appWasBackgrounded) return;
    if (!_canRequestAds ||
      _showingReward ||
        !_appOpenAdIsEligible(appWasBackgrounded: appWasBackgrounded)) {
      _loadAppOpenAd();
      return;
    }
    final ad = _appOpenAd;
    if (ad == null) {
      _foregroundAdPending = true;
      _loadAppOpenAd();
      return;
    }
    _foregroundAdPending = false;
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

  void prepareForForeground() {
    if (!_canRequestAds) return;
    _loadAppOpenAd();
  }

  bool _appOpenAdIsEligible({required bool appWasBackgrounded}) =>
      appWasBackgrounded &&
      !_showingAppOpen &&
      !hasTemporaryAdFreeAccess &&
      (_lastAppOpenShown == null ||
          DateTime.now().difference(_lastAppOpenShown!) >
              const Duration(hours: 4));

  /// Shows a rewarded video for VPN time; unlike [showReward] it ignores and does not grant ad-free access.
  Future<bool> showTimeReward() async {
    await initialize();
    if (!_canRequestAds || _showingReward || _showingAppOpen) return false;
    _showingReward = true;
    final completer = Completer<bool>();
    void finish(bool earned) {
      if (!completer.isCompleted) completer.complete(earned);
    }

    void show(RewardedAd ad) {
      var earned = false;
      ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
        onAdDismissedFullScreenContent: (shownAd) {
          shownAd.dispose();
          finish(earned);
          preloadTimeReward();
        },
        onAdFailedToShowFullScreenContent: (shownAd, _) {
          shownAd.dispose();
          finish(false);
          preloadTimeReward();
        },
      );
      ad.show(onUserEarnedReward: (_, __) => earned = true);
    }

    final readyAd = _timeRewardAd;
    _timeRewardAd = null;
    try {
      if (readyAd != null) {
        show(readyAd);
      } else {
        await RewardedAd.load(
          adUnitId: rewardedId,
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: show,
            onAdFailedToLoad: (_) => finish(false),
          ),
        );
      }
      return await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => false,
      );
    } finally {
      _showingReward = false;
    }
  }

  void preloadTimeReward() {
    if (!_canRequestAds || _timeRewardAd != null || _timeRewardLoading) return;
    _timeRewardLoading = true;
    RewardedAd.load(
      adUnitId: rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _timeRewardLoading = false;
          _timeRewardAd?.dispose();
          _timeRewardAd = ad;
        },
        onAdFailedToLoad: (_) => _timeRewardLoading = false,
      ),
    );
  }

  Future<bool> showReward({required bool interstitial}) async {
    await initialize();
    if (!_canRequestAds ||
        hasTemporaryAdFreeAccess ||
        _showingReward ||
        _showingAppOpen) {
      return false;
    }
    _showingReward = true;
    try {
      final earned = await _loadAndShowAdFreeReward(interstitial: interstitial);
      if (earned) {
        await _grantTemporaryAdFree(
          Duration(minutes: interstitial ? 15 : 30),
        );
      }
      return earned;
    } finally {
      _showingReward = false;
    }
  }

  Future<bool> _loadAndShowAdFreeReward({required bool interstitial}) async {
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
            ad.fullScreenContentCallback =
                FullScreenContentCallback<RewardedAd>(
                  onAdDismissedFullScreenContent: (shownAd) {
                    shownAd.dispose();
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

  Future<bool> offerTemporaryAdFree(
    BuildContext context, {
    required String occasion,
  }) async {
    await initialize();
    if (!canOfferTemporaryAdFree) return false;
    _lastRewardOfferShown = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastRewardOfferKey,
      _lastRewardOfferShown!.millisecondsSinceEpoch,
    );
    if (!context.mounted) return false;
    final watch = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Try Swock ad-free'),
        content: Text(
          'Watch one optional rewarded video to hide ads for 30 minutes. '
          'Your VPN and $occasion remain available if you skip it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Watch video'),
          ),
        ],
      ),
    );
    if (watch != true || !context.mounted) return false;
    return showReward(interstitial: false);
  }

  Future<void> _grantTemporaryAdFree(Duration duration) async {
    _adFreeUntil = DateTime.now().add(duration);
    adFreeAccess.value = true;
    _scheduleAdFreeExpiry();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _adFreeUntilKey,
      _adFreeUntil!.millisecondsSinceEpoch,
    );
  }

  void _scheduleAdFreeExpiry() {
    _adFreeExpiryTimer?.cancel();
    final expiresAt = _adFreeUntil;
    if (expiresAt == null) return;
    final delay = expiresAt.difference(DateTime.now());
    if (delay.isNegative || delay == Duration.zero) {
      _adFreeUntil = null;
      adFreeAccess.value = false;
      unawaited(SharedPreferences.getInstance().then(
        (prefs) => prefs.remove(_adFreeUntilKey),
      ));
      return;
    }
    _adFreeExpiryTimer = Timer(delay, () {
      if (DateTime.now().isBefore(expiresAt)) {
        _scheduleAdFreeExpiry();
        return;
      }
      _adFreeUntil = null;
      adFreeAccess.value = false;
      unawaited(SharedPreferences.getInstance().then(
        (prefs) => prefs.remove(_adFreeUntilKey),
      ));
    });
  }
}
