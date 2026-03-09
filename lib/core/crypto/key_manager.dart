import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Manages cryptographic key pairs for signing proofs.
///
/// On first launch, generates an Ed25519 key pair stored securely in Hive.
/// The private key signs captured media; the public key is embedded in proofs
/// for third-party verification. Keys can optionally be backed up via
/// mnemonic seed phrase.
class KeyManager {
  KeyManager._();
  static final KeyManager instance = KeyManager._();

  late SimpleKeyPair _keyPair;
  late String _deviceId;
  final _algorithm = Ed25519();

  bool _initialized = false;
  bool get isInitialized => _initialized;
  String get deviceId => _deviceId;

  /// Initialize key manager — generates or loads existing key pair.
  Future<void> initialize() async {
    final box = Hive.box('truthlens_keys');

    if (box.containsKey('private_key') && box.containsKey('public_key')) {
      // Load existing keys
      final privateBytes = base64Decode(box.get('private_key') as String);
      final publicBytes = base64Decode(box.get('public_key') as String);

      final privateKey = SimpleKeyPairData(
        privateBytes,
        publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );
      _keyPair = privateKey;
      _deviceId = box.get('device_id') as String;
    } else {
      // Generate new key pair
      _keyPair = await _algorithm.newKeyPair();
      _deviceId = const Uuid().v4();

      // Persist keys
      final privateKeyData = await _keyPair.extractPrivateKeyBytes();
      final publicKey = await _keyPair.extractPublicKey();

      await box.put('private_key', base64Encode(privateKeyData));
      await box.put('public_key', base64Encode(publicKey.bytes));
      await box.put('device_id', _deviceId);
    }

    _initialized = true;
  }

  /// Sign arbitrary data with the device's private key.
  Future<Uint8List> sign(Uint8List data) async {
    final signature = await _algorithm.sign(data, keyPair: _keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verify a signature against data using a public key.
  Future<bool> verify(
    Uint8List data,
    Uint8List signatureBytes,
    Uint8List publicKeyBytes,
  ) async {
    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );
    final signature = Signature(
      signatureBytes,
      publicKey: publicKey,
    );
    return _algorithm.verify(data, signature: signature);
  }

  /// Get the public key bytes for embedding in proofs.
  Future<Uint8List> getPublicKeyBytes() async {
    final publicKey = await _keyPair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  /// Export public key as base64 for sharing / QR codes.
  Future<String> getPublicKeyBase64() async {
    final bytes = await getPublicKeyBytes();
    return base64Encode(bytes);
  }

  /// Compute SHA-256 hash of data.
  static Uint8List sha256Hash(Uint8List data) {
    return Uint8List.fromList(sha256.convert(data).bytes);
  }

  /// Compute SHA-512 hash of data.
  static Uint8List sha512Hash(Uint8List data) {
    return Uint8List.fromList(sha512.convert(data).bytes);
  }

  /// Generate a content-addressable ID from media bytes.
  static String contentId(Uint8List mediaBytes) {
    final hash = sha256Hash(mediaBytes);
    return base64Url.encode(hash).replaceAll('=', '');
  }
}
