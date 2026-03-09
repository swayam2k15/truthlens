/// App-wide constants for TruthLens.

class AppConstants {
  AppConstants._();

  // ── App Info ─────────────────────────────────────────────────
  static const String appName = 'TruthLens';
  static const String appVersion = '1.0.0';
  static const int proofSchemaVersion = 1;
  static const String c2paVersion = '2.0';

  // ── Cryptography ─────────────────────────────────────────────
  static const String signingAlgorithm = 'Ed25519';
  static const String hashAlgorithm = 'SHA-256';
  static const int ed25519SignatureLength = 64;
  static const int sha256HashLength = 32;

  // ── TSA Endpoints ────────────────────────────────────────────
  static const List<String> tsaEndpoints = [
    'https://freetsa.org/tsr',
    'https://timestamp.digicert.com',
    'https://timestamp.sectigo.com',
  ];
  static const Duration tsaTimeout = Duration(seconds: 10);

  // ── NTP Servers ──────────────────────────────────────────────
  static const List<String> ntpServers = [
    'pool.ntp.org',
    'time.google.com',
    'time.apple.com',
    'time.cloudflare.com',
  ];

  // ── Blockchain ───────────────────────────────────────────────
  static const String defaultChain = 'polygon';
  static const Map<String, String> rpcEndpoints = {
    'polygon': 'https://polygon-rpc.com',
    'ethereum': 'https://eth.llamarpc.com',
  };
  static const Map<String, int> chainIds = {
    'polygon': 137,
    'ethereum': 1,
  };
  static const Map<String, String> explorerUrls = {
    'polygon': 'https://polygonscan.com/tx/',
    'ethereum': 'https://etherscan.io/tx/',
  };
  static const int maxMerkleBatchSize = 256;

  // ── Hive Box Names ───────────────────────────────────────────
  static const String proofsBox = 'truthlens_proofs';
  static const String settingsBox = 'truthlens_settings';
  static const String keysBox = 'truthlens_keys';

  // ── Settings Keys ────────────────────────────────────────────
  static const String settingGpsEnabled = 'gps_enabled';
  static const String settingSensorsEnabled = 'sensors_enabled';
  static const String settingNtpEnabled = 'ntp_enabled';
  static const String settingAutoTsa = 'auto_tsa';
  static const String settingAutoBlockchain = 'auto_blockchain';
  static const String settingAutoC2pa = 'auto_c2pa';

  // ── Trust Score Weights ──────────────────────────────────────
  static const int trustSignature = 20;
  static const int trustRfc3161 = 25;
  static const int trustLocalTimestamp = 10;
  static const int trustBlockchain = 25;
  static const int trustC2pa = 15;
  static const int trustGps = 10;
  static const int trustNtp = 5;
  static const int trustMax = 100;

  // ── Trust Levels ─────────────────────────────────────────────
  static const int trustLevelMaximum = 90;
  static const int trustLevelHigh = 70;
  static const int trustLevelModerate = 45;

  // ── Capture ──────────────────────────────────────────────────
  static const Duration timestampUpdateInterval = Duration(milliseconds: 100);
  static const int jpegQuality = 95;
  static const Duration sensorSampleDuration = Duration(milliseconds: 200);

  // ── C2PA Labels ──────────────────────────────────────────────
  static const String c2paCreativeWork = 'stds.schema-org.CreativeWork';
  static const String c2paActions = 'c2pa.actions';
  static const String c2paExif = 'stds.exif';
  static const String c2paGeoCoordinates = 'stds.schema-org.GeoCoordinates';
  static const String c2paTruthLens = 'com.truthlens.proof';
}
