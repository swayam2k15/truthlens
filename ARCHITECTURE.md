# TruthLens — System Architecture

## Overview

TruthLens is a 6-layer attestation pipeline that transforms a simple camera capture into a cryptographically verifiable, independently auditable, tamper-evident proof-of-life record.

Every layer adds an independent verification dimension. Faking one is easy. Faking all six consistently is exponentially harder.

```
┌──────────────────────────────────────────────────────────────────┐
│                        TRUTHLENS PIPELINE                        │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ CAPTURE  │→ │ SIGNING  │→ │TIMESTAMP │→ │BLOCKCHAIN│        │
│  │  LAYER   │  │  LAYER   │  │  LAYER   │  │  LAYER   │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
│       ↓                                          ↓               │
│  ┌──────────┐                              ┌──────────┐         │
│  │  C2PA    │ ←────────────────────────── │ STORAGE  │         │
│  │  LAYER   │                              │  LAYER   │         │
│  └──────────┘                              └──────────┘         │
└──────────────────────────────────────────────────────────────────┘
```

---

## Layer 1: Capture Layer

**Files:** `services/capture_service.dart`, `models/capture_metadata.dart`

### What it does

At the moment the shutter fires, CaptureService simultaneously collects:

| Signal | Source | Anti-Spoof Value |
|--------|--------|-----------------|
| GPS (lat/lon/alt) | Device location services | Cross-check with IP geolocation |
| GPS accuracy | HDOP/VDOP | Low accuracy = possible spoof |
| Accelerometer XYZ | IMU sensor | Must match physics of handheld device |
| Gyroscope XYZ | IMU sensor | Rotation patterns hard to synthesize |
| Magnetometer XYZ | Compass sensor | Environment-specific, hard to fake |
| Barometric pressure | Barometer | Must match altitude claim + local weather |
| Ambient light level | Light sensor | Must match time-of-day claim |
| Battery level | System | Contextual consistency check |
| NTP time offset | NTP server query | Exposes device clock manipulation |
| Network IP hash | Connectivity | Geographic cross-check with GPS |
| Connection type | WiFi/cellular/offline | Context verification |
| Device model/OS | System info | Hardware attestation |
| Camera EXIF | Camera API | Focal length, aperture, ISO, flash |

### Why 10+ signals matter

Any single signal can be faked in isolation. GPS spoofing apps are freely available. Device clocks can be changed in settings. VPNs mask IP addresses. But faking ALL of them simultaneously and consistently (GPS matches IP geolocation matches barometric altitude matches NTP time matches accelerometer gravity vector) is exponentially harder.

### NTP Verification (unique to TruthLens)

No competitor does this. Before capture, the app queries NTP time servers and records the delta between the device clock and true internet time. If a user sets their phone clock to a fake date, the NTP offset (e.g., +259200000ms = 3 days ahead) permanently records the manipulation. This offset is embedded in the signed payload and cannot be altered after signing.

---

## Layer 2: Signing Layer

**Files:** `core/crypto/key_manager.dart`, `core/crypto/proof_signer.dart`

### Key Generation

On first launch, KeyManager generates an **Ed25519 keypair**:

- **Private key**: Stored in device Secure Enclave (iOS) / Keystore (Android). Cannot be extracted, copied, or used on another device. Hardware-bound.
- **Public key**: Stored in Hive, shareable for verification.
- **Device ID**: SHA-256 hash of the public key. Unique device identifier.

Ed25519 was chosen over RSA/ECDSA for: 64-byte signatures (compact), fast signing/verification, deterministic (same input = same signature), and resistance to side-channel attacks.

### Signing Pipeline

```
Raw media bytes
       │
       ▼
SHA-256 hash (32 bytes)
       │
       ▼
Build canonical JSON payload
(keys sorted alphabetically for determinism)
       │
       ├── content_id (SHA-256 of media + timestamp)
       ├── capture_time (ISO 8601 UTC)
       ├── device_id
       ├── GPS coordinates + accuracy
       ├── device_model, os_version, app_version
       ├── media_hash_sha256
       ├── sensor_data (accel, gyro, magneto, light, battery)
       ├── network_info (ip_hash, connection_type)
       ├── ntp_offset_ms
       └── proof_schema_version
       │
       ▼
Ed25519 sign(canonical_payload, private_key)
       │
       ▼
64-byte signature
```

### Canonical JSON

The payload is serialized with **alphabetically sorted keys at every nesting level**. This ensures that the same data always produces the exact same bytes, so the signature is deterministic and verifiable by anyone with the public key.

---

## Layer 3: Timestamp Layer

**Files:** `core/crypto/timestamp_authority.dart`

### RFC 3161 Trusted Timestamping

RFC 3161 is an IETF internet standard used in legal digital signatures, financial compliance, and court-admissible evidence. Here's the protocol:

```
TruthLens                          TSA Server (e.g., DigiCert)
    │                                        │
    │  SHA-256 hash of signed payload        │
    │ ─────────────────────────────────────→ │
    │  (ONLY the hash — never the image)     │
    │                                        │
    │         TimestampToken                 │
    │ ←───────────────────────────────────── │
    │  Contains:                             │
    │  - The hash we sent                    │
    │  - TSA's authoritative server time     │
    │  - TSA's digital signature             │
    │  - TSA's X.509 certificate             │
```

### Why this matters

Device clocks can be changed. TSA timestamps **cannot** — they come from an independent, auditable authority with its own certified clock. The TSA never sees the image, only a hash, so privacy is preserved.

### Fallback strategy

1. Try FreeTSA (freetsa.org) — free, open source
2. Try DigiCert — enterprise grade
3. Try Sectigo — backup
4. If all fail (offline): generate local timestamp, flag as `TimestampSource.local` (lower trust score)

When connectivity returns, the app can upgrade local timestamps to server-verified ones.

---

## Layer 4: Blockchain Layer

**Files:** `core/blockchain/blockchain_anchor.dart`

### Immutable Public Record

Once the proof hash is written to a blockchain transaction and mined into a block, the record is **immutable**. No one — not even TruthLens — can alter or delete it. The block number, transaction hash, and explorer URL become part of the proof.

### Merkle Tree Batching (unique to TruthLens)

Individual blockchain transactions cost $0.01-0.50 each. TruthLens batches up to 256 proofs into a single Merkle tree:

```
                    Root Hash
                   (on-chain)
                   /         \
              Hash AB        Hash CD
             /     \        /     \
         Hash A   Hash B  Hash C  Hash D
           │        │       │       │
        Proof 1  Proof 2  Proof 3  Proof 4
```

**Cost reduction: ~100x** — one transaction anchors hundreds of proofs.

**Individual verification**: Each proof stores its **Merkle path** (the sibling hashes needed to recompute the root). Anyone can verify: take proof hash → apply Merkle path → confirm root matches on-chain transaction.

### Supported chains

- **Polygon** (default): Fast (~2s blocks), cheap (~$0.001 per tx), EVM-compatible
- **Ethereum**: Higher cost but maximum decentralization and permanence
- Architecture supports adding Solana, Avalanche, etc.

---

## Layer 5: C2PA Layer

**Files:** `core/c2pa/c2pa_manifest.dart`

### C2PA Content Credentials

C2PA (Coalition for Content Provenance and Authenticity) is an open standard developed by Adobe, Microsoft, Intel, Truepic, and the BBC. TruthLens generates C2PA 2.0-compliant manifests containing five assertion types:

| Assertion | C2PA Label | Content |
|-----------|-----------|---------|
| Authorship | `stds.schema-org.CreativeWork` | Device identity as author |
| Actions | `c2pa.actions` | `c2pa.created` event with timestamp |
| EXIF | `stds.exif` | Camera metadata (focal length, aperture, ISO) |
| Location | `stds.schema-org.GeoCoordinates` | GPS coordinates |
| TruthLens | `com.truthlens.proof` | Full proof data (signature, blockchain anchors, sensor snapshot, trust score) |

### Why C2PA matters

Without C2PA, TruthLens proofs can only be verified inside the TruthLens ecosystem. With C2PA, proofs are readable by **any C2PA-compatible tool**: Adobe Content Authenticity, Truepic, media organizations, news agencies, etc. This is what makes TruthLens interoperable rather than proprietary.

The custom `com.truthlens.proof` assertion embeds our full proof data inside the standard C2PA envelope — extending the standard without breaking it.

---

## Layer 6: Storage & Verification

**Files:** `services/proof_storage_service.dart`, `services/attestation_service.dart`, `models/proof_record.dart`

### Offline-First Storage

All proofs stored locally in Hive (lightweight key-value DB, no native dependencies). Works fully offline. Proofs are stored as signed JSON keyed by content ID.

### Trust Score (0-100)

| Component | Points | Rationale |
|-----------|--------|-----------|
| Ed25519 Signature | +20 | Device-bound, tamper-evident |
| RFC 3161 Timestamp | +25 | Independent third-party time proof |
| Blockchain Anchor | +25 | Immutable public record |
| C2PA Manifest | +15 | Industry-standard interoperability |
| GPS Location | +10 | Geospatial context |
| NTP Verification | +5 | Clock tampering detection |

**Levels:** Maximum (90+) → High (70+) → Moderate (45+) → Basic (<45)

### Independent Verification

AttestationService provides full verification:

1. **Signature check**: Recompute Ed25519 signature against public key
2. **Hash check**: Recompute SHA-256 of media, compare to stored hash
3. **Timestamp check**: Validate RFC 3161 token against TSA certificate
4. **Blockchain check**: Query chain for transaction, verify Merkle proof
5. **Metadata consistency**: Cross-check GPS vs. IP geolocation, NTP offset, sensor physics

---

## File Map

```
truthlens/
├── lib/
│   ├── main.dart                              # App entry, Hive init, theming
│   ├── core/
│   │   ├── crypto/
│   │   │   ├── key_manager.dart               # Ed25519 keypair, Secure Enclave
│   │   │   ├── proof_signer.dart              # Signing pipeline, canonical JSON
│   │   │   └── timestamp_authority.dart       # RFC 3161 TSA client
│   │   ├── blockchain/
│   │   │   └── blockchain_anchor.dart         # EVM anchoring, Merkle batching
│   │   └── c2pa/
│   │       └── c2pa_manifest.dart             # C2PA 2.0 manifest builder
│   ├── models/
│   │   ├── capture_metadata.dart              # 10+ sensor metadata fields
│   │   └── proof_record.dart                  # Proof structure, trust score
│   ├── services/
│   │   ├── capture_service.dart               # Camera + sensor collection
│   │   ├── attestation_service.dart           # Pipeline orchestrator + verifier
│   │   └── proof_storage_service.dart         # Hive persistence, export
│   ├── screens/
│   │   ├── capture/capture_screen.dart        # Live camera, timestamp overlay
│   │   ├── verify/verify_screen.dart          # Verification UI, trust badge
│   │   ├── history/history_screen.dart        # Proof timeline, export
│   │   └── settings/settings_screen.dart      # Identity, toggles, config
│   └── widgets/
│       ├── trust_badge.dart                   # Circular score indicator
│       └── proof_card.dart                    # 5-layer attestation display
├── docs/
│   ├── ARCHITECTURE.md                        # This file
│   └── architecture-diagram.jsx               # Interactive React diagram
├── pubspec.yaml                               # Dependencies
├── README.md                                  # Project overview + competitor analysis
├── .gitignore
├── LICENSE (MIT)
└── analysis_options.yaml
```

---

## Competitive Advantage Matrix

| Feature | TruthLens | Truepic | ProofMode | Numbers Protocol | Proofie |
|---------|-----------|---------|-----------|-----------------|---------|
| Ed25519 device signature | ✅ | ✅ | ✅ (PGP) | ❌ | ✅ |
| RFC 3161 trusted timestamp | ✅ | ❌ | ❌ | ❌ | ❌ |
| Blockchain anchoring | ✅ | ❌ | Optional | ✅ | ✅ |
| Merkle tree batching | ✅ | ❌ | ❌ | ❌ | ❌ |
| C2PA Content Credentials | ✅ | ✅ | ✅ | ❌ | ❌ |
| NTP clock verification | ✅ | ❌ | ❌ | ❌ | ❌ |
| Multi-sensor anti-spoof | ✅ (10+) | Limited | ❌ | ❌ | ❌ |
| Trust score system | ✅ | ❌ | ❌ | ❌ | ❌ |
| Offline-first | ✅ | ❌ | ✅ | ❌ | ❌ |
| Open source | ✅ | ❌ | ✅ | Partial | ❌ |
| Cross-platform (Flutter) | ✅ | iOS/Android | Android | iOS | iOS |

---

## Security Model

### Threat Model

| Threat | Mitigation |
|--------|-----------|
| Clock manipulation | NTP offset detection + RFC 3161 TSA |
| GPS spoofing | Cross-check with IP geolocation + barometric altitude |
| Photo from screen | Sensor data inconsistency (no natural motion, wrong light level) |
| Key extraction | Secure Enclave / Keystore — hardware-bound, non-exportable |
| Proof tampering | Ed25519 signature invalidated by any change |
| Service shutdown | Blockchain anchors persist independently on public chain |
| Deepfake injection | C2PA chain-of-custody proves capture device, not just content |

### Privacy Design

- TSA servers receive ONLY hashes, never images
- Blockchain stores ONLY hashes, never content
- Network IP is hashed (SHA-256) before storage — original IP never persisted
- All processing happens on-device
- No cloud accounts required
- No telemetry or analytics

---

## Future Roadmap

1. **Hardware attestation** — Android SafetyNet / iOS DeviceCheck integration
2. **Liveness detection** — ML-based facial liveness to prevent photo-of-photo attacks
3. **QR code verification** — Scan a TruthLens QR to verify any proof
4. **Witness network** — Multiple devices co-signing the same event for consensus
5. **Legal compliance pack** — Pre-formatted exports for court admissibility
6. **API / SDK** — Allow third-party apps to request TruthLens attestation
