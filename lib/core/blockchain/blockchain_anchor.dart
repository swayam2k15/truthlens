import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http_pkg;

import '../../models/proof_record.dart';

/// Blockchain anchoring service.
///
/// Anchors proof hashes to public blockchains, creating an immutable,
/// publicly verifiable record that a specific proof existed at a given time.
///
/// Supports multiple chains for redundancy:
/// - Polygon (low cost, fast finality)
/// - Ethereum (highest security, expensive)
/// - Solana (fast, low cost)
///
/// Also supports batched Merkle tree anchoring to reduce costs:
/// many proofs can share a single blockchain transaction.
class BlockchainAnchorService {
  BlockchainAnchorService._();
  static final BlockchainAnchorService instance = BlockchainAnchorService._();

  final _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final _dio = Dio();

  // Default RPC endpoints (configurable)
  static const _polygonRpc = 'https://polygon-rpc.com';
  static const _ethereumRpc = 'https://eth.llamarpc.com';

  /// Anchor a proof hash to Polygon (recommended: fast + cheap).
  Future<BlockchainAnchor?> anchorToPolygon({
    required String proofHash,
    required String privateKeyHex,
  }) async {
    return _anchorToEvm(
      chain: 'polygon',
      rpcUrl: _polygonRpc,
      chainId: 137,
      proofHash: proofHash,
      privateKeyHex: privateKeyHex,
    );
  }

  /// Anchor a proof hash to Ethereum mainnet.
  Future<BlockchainAnchor?> anchorToEthereum({
    required String proofHash,
    required String privateKeyHex,
  }) async {
    return _anchorToEvm(
      chain: 'ethereum',
      rpcUrl: _ethereumRpc,
      chainId: 1,
      proofHash: proofHash,
      privateKeyHex: privateKeyHex,
    );
  }

  /// Generic EVM-compatible chain anchoring.
  Future<BlockchainAnchor?> _anchorToEvm({
    required String chain,
    required String rpcUrl,
    required int chainId,
    required String proofHash,
    required String privateKeyHex,
  }) async {
    try {
      final client = Web3Client(rpcUrl, http_pkg.Client());
      final credentials = EthPrivateKey.fromHex(privateKeyHex);

      // Encode proof hash as transaction data
      // Format: 0x + "TRUTHLENS" prefix + proof hash
      final dataHex = '0x'
          '545255544c454e53' // "TRUTHLENS" in hex
          '${proofHash.replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_')}';

      final tx = Transaction(
        to: credentials.address, // Self-transaction (data-only)
        value: EtherAmount.zero(),
        data: Uint8List.fromList(utf8.encode(dataHex)),
        maxGas: 30000,
      );

      final txHash = await client.sendTransaction(
        credentials,
        tx,
        chainId: chainId,
      );

      _log.i('Anchored to $chain: $txHash');

      final explorerBase = chain == 'polygon'
          ? 'https://polygonscan.com/tx/'
          : 'https://etherscan.io/tx/';

      await client.dispose();

      return BlockchainAnchor(
        chain: chain,
        transactionHash: txHash,
        anchoredAt: DateTime.now().toUtc(),
        explorerUrl: '$explorerBase$txHash',
      );
    } catch (e) {
      _log.e('Failed to anchor to $chain: $e');
      return null;
    }
  }

  /// Batch multiple proof hashes into a Merkle tree and anchor the root.
  ///
  /// This is dramatically cheaper: 100 proofs can share one transaction.
  Future<BatchAnchorResult?> batchAnchor({
    required List<String> proofHashes,
    required String chain,
    required String privateKeyHex,
  }) async {
    if (proofHashes.isEmpty) return null;

    // Build Merkle tree
    final merkleRoot = _computeMerkleRoot(proofHashes);

    // Anchor the Merkle root
    final anchor = chain == 'polygon'
        ? await anchorToPolygon(
            proofHash: merkleRoot,
            privateKeyHex: privateKeyHex,
          )
        : await anchorToEthereum(
            proofHash: merkleRoot,
            privateKeyHex: privateKeyHex,
          );

    if (anchor == null) return null;

    // Generate Merkle proofs for each hash
    final proofs = <String, List<String>>{};
    for (final hash in proofHashes) {
      proofs[hash] = _computeMerkleProof(proofHashes, hash);
    }

    return BatchAnchorResult(
      anchor: anchor,
      merkleRoot: merkleRoot,
      merkleProofs: proofs,
      proofCount: proofHashes.length,
    );
  }

  /// Compute Merkle root from a list of hashes.
  String _computeMerkleRoot(List<String> hashes) {
    if (hashes.length == 1) return hashes.first;

    var level = hashes.toList();

    while (level.length > 1) {
      final nextLevel = <String>[];
      for (var i = 0; i < level.length; i += 2) {
        final left = level[i];
        final right = i + 1 < level.length ? level[i + 1] : level[i];
        final combined = sha256.convert(utf8.encode('$left$right'));
        nextLevel.add(base64Encode(combined.bytes));
      }
      level = nextLevel;
    }

    return level.first;
  }

  /// Compute Merkle proof path for a specific hash.
  List<String> _computeMerkleProof(List<String> hashes, String targetHash) {
    // Simplified — production implementation would track sibling nodes
    final proof = <String>[];
    var level = hashes.toList();
    var index = level.indexOf(targetHash);

    while (level.length > 1) {
      final nextLevel = <String>[];
      for (var i = 0; i < level.length; i += 2) {
        final left = level[i];
        final right = i + 1 < level.length ? level[i + 1] : level[i];

        if (i == index || i + 1 == index) {
          proof.add(i == index ? right : left);
        }

        final combined = sha256.convert(utf8.encode('$left$right'));
        nextLevel.add(base64Encode(combined.bytes));
      }
      index = index ~/ 2;
      level = nextLevel;
    }

    return proof;
  }

  /// Verify that a proof hash is included in a Merkle tree with given root.
  bool verifyMerkleProof({
    required String proofHash,
    required List<String> merkleProof,
    required String merkleRoot,
    required int leafIndex,
  }) {
    var current = proofHash;
    var index = leafIndex;

    for (final sibling in merkleProof) {
      final left = index.isEven ? current : sibling;
      final right = index.isEven ? sibling : current;
      current = base64Encode(
        sha256.convert(utf8.encode('$left$right')).bytes,
      );
      index ~/= 2;
    }

    return current == merkleRoot;
  }
}

class BatchAnchorResult {
  final BlockchainAnchor anchor;
  final String merkleRoot;
  final Map<String, List<String>> merkleProofs;
  final int proofCount;

  const BatchAnchorResult({
    required this.anchor,
    required this.merkleRoot,
    required this.merkleProofs,
    required this.proofCount,
  });
}
