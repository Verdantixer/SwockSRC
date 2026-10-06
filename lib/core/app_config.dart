class AppConfig {
  static const String appName = 'Swock';
  static const String channelName = 'com.swock.vpn/channel';
  static const String eventChannelName = 'com.swock.vpn/events';
  static const String storageKey = 'swock_profiles_v1';
  static const String secureStorageKey = 'swock_secure_profiles_v1';
  static const int defaultPingTimeoutMs = 4000;
  static const int maxLogs = 500;
  static const List<String> supportedAbis = [
    'armeabi-v7a',
    'arm64-v8a',
    'x86',
    'x86_64',
  ];
}
