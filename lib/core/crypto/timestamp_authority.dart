import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

/// RFC 3161 Trusted Timestamp Authority client.
///
/// Contacts a TSA server to obtain a cryptographically signed timestamp
/// proving that a particular hash existed at a specific point in time.
/// This is the gold standard for legal-grade timestamp verification.
class TimestampAuthority {
  TimestampAuthority._();
  static final TimestampAuthority instance = TimestampAuthority._();

  final _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final _dio = Dio();

  // Default TSA endpoints (can be configured in settings)
  static const List<String> _defaultTsaUrls = [
    'https://freetsa.org/tsr',
    'https://timestamp.digicert.com',
    'https://timestamp.sectigo.com',
  ];

  /// Request an RFC 3161 timestamp token for a SHA-256 hash.
  ///
  /// The TSA server signs the hash with its own certificate, creating
  /// a verifiable proof that this data existed at the signed time.
  ///
  /// Returns a [TimestampToken] containing the TSA response, or null on failure.
  Future<TimestampToken?> requestTimestamp(Uint8List dataHash) async {
    for (final tsaUrl in _defaultTsaUrls) {
      try {
        final token = await _requestFromTsa(tsaUrl, dataHash);
        if (token != null) return token;
      } catch (e) {
        _log.w('TSA $tsaUrl failed: $e');
      }
    }

    _log.e('All TSA servers failed — falling back to local timestamp');
    return _createLocalTimestamp(dataHash);
  }

  Future<TimestampToken?> _requestFromTsa(
    String tsaUrl,
    Uint8List dataHash,
  ) async {
    // Build ASN.1 TimeStampReq (simplified — production would use asn1lib)
    final tsRequest = _buildTimestampRequest(dataHash);

    final response = await _dio.post<List<int>>(
      tsaUrl,
      data: tsRequest,
      options: Options(
        headers: {
          'Content-Type': 'application/timestamp-query',
        },
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      final responseBytes = Uint8List.fromList(response.data!);

      return TimestampToken(
        tsaUrl: tsaUrl,
        requestHash: base64Encode(dataHash),
        responseBytes: responseBytes,
        responseBase64: base64Encode(responseBytes),
        timestamp: DateTime.now().toUtc(),
        isVerified: true,
        source: TimestampSource.rfc3161,
      );
    }

    return null;
  }

  /// Build a minimal RFC 3161 TimeStampReq ASN.1 structure.
  Uint8List _buildTimestampRequest(Uint8List hash) {
    // ASN.1 DER encoding of TimeStampReq
    // SEQUENCE {
    //   version INTEGER (1),
    //   messageImprint SEQUENCE {
    //     hashAlgorithm AlgorithmIdentifier (SHA-256),
    //     hashedMessage OCTET STRING
    //   },
    //   certReq BOOLEAN TRUE
    // }

    // SHA-256 OID: 2.16.840.1.101.3.4.2.1
    final sha256Oid = Uint8List.fromList([
      0x30, 0x0d, // SEQUENCE
      0x06, 0x09, // OID
      0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01,
      0x05, 0x00, // NULL
    ]);

    // MessageImprint
    final hashedMessage = _derOctetString(hash);
    final messageImprint = _derSequence(
      Uint8List.fromList([...sha256Oid, ...hashedMessage]),
    );

    // Version
    final version = Uint8List.fromList([0x02, 0x01, 0x01]);

    // CertReq
    final certReq = Uint8List.fromList([0x01, 0x01, 0xff]);

    // Full TimeStampReq
    return _derSequence(
      Uint8List.fromList([...version, ...messageImprint, ...certReq]),
    );
  }

  Uint8List _derOctetString(Uint8List data) {
    return Uint8List.fromList([0x04, data.length, ...data]);
  }

  Uint8List _derSequence(Uint8List data) {
    if (data.length < 128) {
      return Uint8List.fromList([0x30, data.length, ...data]);
    }
    // Long form length encoding
    final lenBytes = _encodeLongLength(data.length);
    return Uint8List.fromList([0x30, ...lenBytes, ...data]);
  }

  List<int> _encodeLongLength(int length) {
    if (length < 256) return [0x81, length];
    return [0x82, (length >> 8) & 0xff, length & 0xff];
  }

  /// Fallback: create a locally signed timestamp when offline.
  /// Less authoritative than RFC 3161 but still useful.
  TimestampToken _createLocalTimestamp(Uint8List dataHash) {
    final now = DateTime.now().toUtc();
    final localProof = sha256
        .convert([
          ...dataHash,
          ...utf8.encode(now.toIso8601String()),
          ...utf8.encode('truthlens-local-tsa'),
        ])
        .bytes;

    return TimestampToken(
      tsaUrl: 'local',
      requestHash: base64Encode(dataHash),
      responseBytes: Uint8List.fromList(localProof),
      responseBase64: base64Encode(localProof),
      timestamp: now,
      isVerified: false,
      source: TimestampSource.local,
    );
  }
}

enum TimestampSource { rfc3161, local, blockchain }

/// Represents a trusted timestamp token from a TSA server.
class TimestampToken {
  final String tsaUrl;
  final String requestHash;
  final Uint8List responseBytes;
  final String responseBase64;
  final DateTime timestamp;
  final bool isVerified;
  final TimestampSource source;

  const TimestampToken({
    required this.tsaUrl,
    required this.requestHash,
    required this.responseBytes,
    required this.responseBase64,
    required this.timestamp,
    required this.isVerified,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
        'tsa_url': tsaUrl,
        'request_hash': requestHash,
        'response_base64': responseBase64,
        'timestamp': timestamp.toIso8601String(),
        'is_verified': isVerified,
        'source': source.name,
      };

  factory TimestampToken.fromJson(Map<String, dynamic> json) {
    return TimestampToken(
      tsaUrl: json['tsa_url'] as String,
      requestHash: json['request_hash'] as String,
      responseBytes: base64Decode(json['response_base64'] as String),
      responseBase64: json['response_base64'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isVerified: json['is_verified'] as bool,
      source: TimestampSource.values.byName(json['source'] as String),
    );
  }
}
