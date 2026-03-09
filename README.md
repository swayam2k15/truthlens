# TruthLens

**Tamper-proof, timestamped proof-of-life camera app.**

TruthLens captures photos and videos with cryptographically verifiable proof of *when*, *where*, and *by whom* they were taken. It combines four layers of verification that no existing competitor fully integrates into a single mobile app.

## The Problem

In the age of deepfakes and AI-generated media, there is no widely-adopted, user-friendly way to prove that a photo or video is authentic — that it was genuinely captured at a specific time and place, by a real device, and hasn't been tampered with since.

Existing solutions (Truepic, ProofMode, Numbers Protocol) each address parts of this problem, but none combine all verification layers in a single, open-source, privacy-respecting mobile app.

## How TruthLens Works

Every capture goes through a **4-layer attestation pipeline**:

```
Camera Capture
     │
     ├─ 1. DEVICE SIGNING ──── Ed25519 signature with device-bound key pair
     │
     ├─ 2. TRUSTED TIMESTAMP ─ RFC 3161 token from TSA server (DigiCert, FreeTSA)
     │
     ├─ 3. BLOCKCHAIN ANCHOR ─ Hash anchored to Polygon/Ethereum (immutable public proof)
     │
     └─ 4. C2PA MANIFEST ───── Industry-standard Content Credentials (Adobe/Truepic compatible)
```

At the moment of capture, TruthLens also records:
- GPS coordinates (lat/lon/altitude/accuracy)
- Device sensor snapshots (accelerometer, gyroscope, magnetometer)
- NTP time offset (verifies device clock isn't spoofed)
- Network context (connection type, hashed IP)
- Barometric pressure, light level, battery state
- Camera EXIF data (focal length, aperture, ISO, exposure)

**The key insight:** spoofing one signal is easy. Spoofing ALL signals consistently and simultaneously is exponentially harder.

## Competitive Landscape

| Feature | TruthLens | Truepic | ProofMode | Numbers Protocol | Proofie |
|---------|-----------|---------|-----------|-----------------|---------|
| Ed25519 device signatures | ✅ | ✅ | ✅ | ❌ | ✅ |
| RFC 3161 trusted timestamps | ✅ | ❌ | ❌ | ❌ | ❌ |
| Blockchain anchoring | ✅ | ❌ | Optional | ✅ | ✅ |
| C2PA Content Credentials | ✅ | ✅ | ✅ | ❌ | ❌ |
| Multi-sensor metadata | ✅ | Partial | Partial | ❌ | ❌ |
| NTP time verification | ✅ | ❌ | ❌ | ❌ | ❌ |
| Open source | ✅ | ❌ | ✅ | Partial | ❌ |
| Offline-first | ✅ | ❌ | ✅ | ❌ | ❌ |
| Trust score system | ✅ | ❌ | ❌ | ❌ | ❌ |
| Batch Merkle anchoring | ✅ | ❌ | ❌ | ❌ | ❌ |
| Free / no subscription | ✅ | ❌ | ✅ | ❌ | ❌ |

### Where TruthLens Beats the Competition

1. **Full-stack verification in one app** — No existing app combines all 4 layers (signature + RFC 3161 + blockchain + C2PA)
2. **Trust score system** — Quantified 0-100 trust rating based on how many verification layers are active
3. **Multi-sensor anti-spoofing** — Captures 10+ independent signals that must all be consistent
4. **NTP time verification** — Detects device clock manipulation (no competitor does this)
5. **Batch Merkle tree anchoring** — 100x cheaper blockchain costs vs. per-proof anchoring
6. **Offline-first with graceful degradation** — Works without internet, upgrades proof when connectivity returns
7. **Open source** — Fully auditable, unlike Truepic's closed-source approach
8. **Privacy-respecting** — All data stays on-device; blockchain stores only hashes

## Architecture

```
lib/
├── main.dart                          # App entry point
├── core/
│   ├── crypto/
│   │   ├── key_manager.dart           # Ed25519 key pair management
│   │   ├── timestamp_authority.dart   # RFC 3161 TSA client
│   │   └── proof_signer.dart          # Full signing pipeline orchestrator
│   ├── blockchain/
│   │   └── blockchain_anchor.dart     # EVM chain anchoring + Merkle trees
│   └── c2pa/
│       └── c2pa_manifest.dart         # C2PA manifest builder
├── models/
│   ├── capture_metadata.dart          # Metadata collected at capture
│   └── proof_record.dart              # Complete proof data structure
├── services/
│   ├── capture_service.dart           # Camera + metadata collection
│   ├── attestation_service.dart       # High-level attestation orchestrator
│   └── proof_storage_service.dart     # Hive-based local storage
├── screens/
│   ├── capture/capture_screen.dart    # Camera UI with live timestamp overlay
│   ├── verify/verify_screen.dart      # Proof verification & detail view
│   ├── history/history_screen.dart    # Proof history timeline
│   └── settings/settings_screen.dart  # Configuration
└── widgets/
    ├── trust_badge.dart               # Circular trust score indicator
    └── proof_card.dart                # Detailed proof attestation card
```

## Tech Stack

- **Framework:** Flutter 3.2+
- **State Management:** Riverpod
- **Cryptography:** Ed25519 (via `cryptography` package), SHA-256
- **Timestamping:** RFC 3161 (FreeTSA, DigiCert, Sectigo)
- **Blockchain:** web3dart (Polygon, Ethereum)
- **Storage:** Hive (offline-first, no native deps)
- **Content Credentials:** C2PA 2.0 specification

## Getting Started

```bash
# Clone the repo
git clone https://github.com/yourusername/truthlens.git
cd truthlens

# Install dependencies
flutter pub get

# Run on device (camera requires physical device)
flutter run
```

### Prerequisites

- Flutter SDK 3.2+
- Physical device (camera not available on emulator)
- For blockchain anchoring: Polygon wallet with MATIC for gas

## Use Cases

- **Insurance** — Timestamped damage photos for claims
- **Journalism** — Verified media for news organizations
- **Legal evidence** — Admissible digital evidence with chain of custody
- **Compliance** — Field inspections with certified timestamps
- **Real estate** — Property condition documentation
- **Supply chain** — Verified product/shipment photos
- **Anti-deepfake** — Proving media authenticity in the AI era

## Roadmap

- [ ] QR code proof sharing & scanning
- [ ] Solana blockchain support
- [ ] Video frame-by-frame attestation
- [ ] Liveness detection (anti-replay)
- [ ] Browser extension for web verification
- [ ] API for third-party integrations
- [ ] Hardware attestation (Android SafetyNet / iOS DeviceCheck)
- [ ] Decentralized identity (DID) integration

## License

MIT License — see [LICENSE](LICENSE) for details.
