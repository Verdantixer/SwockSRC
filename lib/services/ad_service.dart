import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  static const appOpenId = '';
  static const nativeId = '';
  static const rewardedInterstitialId = '';
  static const rewardedId = '';

  static const _adFreeUntilKey = 'temporary_ad_free_until_ms';
  static const _lastRewardOfferKey = 'last_ad_free_offer_ms';

  Future<void>? _initialization;
  final bool _canRequestAds = false;
  Timer? _adFreeExpiryTimer;
  DateTime? _lastRewardOfferShown;
  DateTime? _adFreeUntil;
  final ValueNotifier<bool> adFreeAccess = ValueNotifier(false);

  bool get canRequestAds => _canRequestAds;
  bool get hasTemporaryAdFreeAccess =>
      _adFreeUntil != null && DateTime.now().isBefore(_adFreeUntil!);
  bool get canOfferTemporaryAdFree => false;

  Future<bool> privacyOptionsRequired() async => false;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _restoreRewardState();
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

  Future<void> showPrivacyOptions() async {}

  void showAppOpenIfReady({required bool appWasBackgrounded}) {}

  void prepareForForeground() {}

  Future<bool> showTimeReward() async => false;

  void preloadTimeReward() {}

  Future<bool> showReward({required bool interstitial}) async => false;

  Future<bool> offerTemporaryAdFree(
    BuildContext context, {
    required String occasion,
  }) async => false;

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
