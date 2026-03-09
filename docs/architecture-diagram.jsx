import { useState } from "react";

const COLORS = {
  bg: "#0f1117",
  card: "#1a1d27",
  cardHover: "#232738",
  border: "#2a2e3d",
  accent: "#f59e0b",
  green: "#22c55e",
  blue: "#3b82f6",
  purple: "#a855f7",
  red: "#ef4444",
  cyan: "#06b6d4",
  text: "#e2e8f0",
  textMuted: "#94a3b8",
  textDim: "#64748b",
};

const layers = [
  {
    id: "capture",
    title: "1. CAPTURE LAYER",
    color: COLORS.blue,
    icon: "📸",
    desc: "Camera + multi-sensor metadata collection at moment of capture",
    components: [
      {
        name: "CaptureService",
        file: "services/capture_service.dart",
        detail: "Initializes camera, captures photo/video bytes, collects 10+ simultaneous sensor readings",
      },
      {
        name: "CaptureMetadata",
        file: "models/capture_metadata.dart",
        detail: "GPS (lat/lon/alt/accuracy), accelerometer XYZ, gyroscope XYZ, magnetometer, barometric pressure, light level, battery %, NTP offset, network IP hash, device model, OS version, EXIF data",
      },
      {
        name: "NTP Verification",
        file: "core/crypto/timestamp_authority.dart",
        detail: "Cross-checks device clock against NTP servers. Records offset in ms — exposes clock tampering. If device says 14:00 but NTP says 14:03, the 3-minute gap is permanently recorded",
      },
    ],
    flow: "Raw bytes + metadata →",
  },
  {
    id: "signing",
    title: "2. SIGNING LAYER",
    color: COLORS.green,
    icon: "🔐",
    desc: "Cryptographic binding of content to device identity",
    components: [
      {
        name: "KeyManager",
        file: "core/crypto/key_manager.dart",
        detail: "Generates Ed25519 keypair on first launch. Private key stored in device Secure Enclave (iOS) / Keystore (Android). Never leaves hardware. Device-bound identity.",
      },
      {
        name: "ProofSigner",
        file: "core/crypto/proof_signer.dart",
        detail: "1) SHA-256 hash of raw media → 2) Build canonical JSON payload (keys sorted alphabetically for determinism) → 3) Sign payload with Ed25519 private key → 4) Package into ProofRecord",
      },
      {
        name: "Canonical Payload",
        file: "core/crypto/proof_signer.dart",
        detail: "Deterministic JSON with sorted keys ensures identical bytes every time. Includes: content_id, capture_time, device_id, GPS, sensor snapshot, media_hash, network_info, ntp_offset, schema version",
      },
    ],
    flow: "Signed proof →",
  },
  {
    id: "timestamp",
    title: "3. TIMESTAMP LAYER",
    color: COLORS.accent,
    icon: "⏱️",
    desc: "Third-party cryptographic proof of existence at a specific time",
    components: [
      {
        name: "TimestampAuthority",
        file: "core/crypto/timestamp_authority.dart",
        detail: "RFC 3161 client. Sends ONLY the SHA-256 hash to TSA server (never the image). TSA signs it with their certificate + their authoritative clock time. Returns a TimestampToken.",
      },
      {
        name: "TSA Servers",
        file: "—",
        detail: "FreeTSA (freetsa.org) — free, open. DigiCert — enterprise grade. Sectigo — backup. App tries all three with fallback to local timestamp if offline.",
      },
      {
        name: "Why this matters",
        file: "—",
        detail: "Device clocks can be faked. TSA timestamps CANNOT — they come from an independent, auditable authority. Same standard used in legal digital signatures, court evidence, and financial compliance.",
      },
    ],
    flow: "Timestamped proof →",
  },
  {
    id: "blockchain",
    title: "4. BLOCKCHAIN LAYER",
    color: COLORS.purple,
    icon: "⛓️",
    desc: "Immutable public ledger anchoring — proof exists forever",
    components: [
      {
        name: "BlockchainAnchorService",
        file: "core/blockchain/blockchain_anchor.dart",
        detail: "Writes proof hash to Polygon (default) or Ethereum. Once mined into a block, the record is IMMUTABLE — no one can alter or delete it, not even TruthLens.",
      },
      {
        name: "Merkle Tree Batching",
        file: "core/blockchain/blockchain_anchor.dart",
        detail: "Instead of 1 transaction per proof ($0.01-0.50 each), batches up to 256 proofs into a single Merkle tree. Only the root hash goes on-chain. Individual proofs verified via Merkle path. ~100x cheaper.",
      },
      {
        name: "Verification",
        file: "—",
        detail: "Anyone can verify: take the proof hash → compute Merkle path → confirm root matches on-chain transaction. Block explorer URL stored in proof record for public auditability.",
      },
    ],
    flow: "Anchored proof →",
  },
  {
    id: "c2pa",
    title: "5. C2PA LAYER",
    color: COLORS.cyan,
    icon: "📜",
    desc: "Industry-standard Content Credentials for cross-platform verification",
    components: [
      {
        name: "C2PAManifestBuilder",
        file: "core/c2pa/c2pa_manifest.dart",
        detail: "Generates C2PA 2.0 manifests with 5 assertion types: CreativeWork (authorship), Actions (capture event), EXIF metadata, GeoCoordinates, and TruthLens custom assertion (full proof data).",
      },
      {
        name: "Interoperability",
        file: "—",
        detail: "C2PA manifests are readable by Adobe Content Authenticity, Truepic, Microsoft, Intel tools, and any C2PA-compatible verifier. This makes TruthLens proofs verifiable OUTSIDE our ecosystem.",
      },
      {
        name: "Custom Assertion",
        file: "core/c2pa/c2pa_manifest.dart",
        detail: "com.truthlens.proof assertion embeds our full proof data (signature, blockchain anchors, sensor snapshot, trust score) inside the standard C2PA envelope — extending the standard without breaking it.",
      },
    ],
    flow: "Complete proof record →",
  },
  {
    id: "storage",
    title: "6. STORAGE & VERIFICATION",
    color: COLORS.red,
    icon: "🛡️",
    desc: "Offline-first persistence + independent verification engine",
    components: [
      {
        name: "ProofStorageService",
        file: "services/proof_storage_service.dart",
        detail: "Hive-based local DB. Proofs stored as signed JSON keyed by content ID. Works fully offline. Supports export/backup of entire proof history.",
      },
      {
        name: "AttestationService",
        file: "services/attestation_service.dart",
        detail: "Orchestrates the full pipeline: capture → sign → timestamp → anchor → C2PA → store. Also provides independent verification: re-checks signature, validates timestamp, confirms blockchain anchor, recomputes trust score.",
      },
      {
        name: "Trust Score (0-100)",
        file: "models/proof_record.dart",
        detail: "Signature: +20 | RFC 3161 TSA: +25 | Blockchain: +25 | C2PA: +15 | GPS: +10 | NTP: +5. Score reflects how many independent verification layers are active. Maximum (90+), High (70+), Moderate (45+), Basic (<45).",
      },
    ],
    flow: "✓ Verified",
  },
];

const antiSpoofing = [
  { signal: "GPS Coordinates", fake: "Easy (spoofing apps)", crossCheck: "Cross-referenced with IP geolocation and barometric altitude" },
  { signal: "Device Clock", fake: "Easy (settings change)", crossCheck: "NTP offset exposes discrepancy. TSA provides independent time" },
  { signal: "Accelerometer/Gyro", fake: "Hard (needs hardware)", crossCheck: "Physics must match — gravity vector, motion patterns" },
  { signal: "Barometric Pressure", fake: "Very hard", crossCheck: "Must match altitude claim and local weather data" },
  { signal: "Network IP Hash", fake: "Moderate (VPN)", crossCheck: "Geographic mismatch with GPS triggers flag" },
  { signal: "Device Attestation", fake: "Very hard", crossCheck: "Ed25519 key in Secure Enclave — cannot be extracted or cloned" },
  { signal: "All Simultaneously", fake: "Extremely hard", crossCheck: "Faking 10+ signals consistently in real-time is exponentially difficult" },
];

function LayerCard({ layer, isExpanded, onToggle }) {
  return (
    <div
      style={{
        background: isExpanded ? COLORS.cardHover : COLORS.card,
        border: `1px solid ${isExpanded ? layer.color : COLORS.border}`,
        borderRadius: 12,
        padding: 20,
        marginBottom: 12,
        cursor: "pointer",
        transition: "all 0.2s ease",
      }}
      onClick={onToggle}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        <span style={{ fontSize: 28 }}>{layer.icon}</span>
        <div style={{ flex: 1 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span
              style={{
                fontSize: 13,
                fontWeight: 700,
                letterSpacing: 1.2,
                color: layer.color,
                fontFamily: "monospace",
              }}
            >
              {layer.title}
            </span>
            {layer.flow && (
              <span style={{ fontSize: 11, color: COLORS.textDim, marginLeft: "auto" }}>
                {layer.flow}
              </span>
            )}
          </div>
          <div style={{ fontSize: 13, color: COLORS.textMuted, marginTop: 4 }}>
            {layer.desc}
          </div>
        </div>
        <span
          style={{
            fontSize: 18,
            color: COLORS.textDim,
            transform: isExpanded ? "rotate(180deg)" : "rotate(0deg)",
            transition: "transform 0.2s",
          }}
        >
          ▼
        </span>
      </div>

      {isExpanded && (
        <div style={{ marginTop: 16, display: "flex", flexDirection: "column", gap: 12 }}>
          {layer.components.map((comp, i) => (
            <div
              key={i}
              style={{
                background: COLORS.bg,
                borderRadius: 8,
                padding: 14,
                borderLeft: `3px solid ${layer.color}`,
              }}
            >
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <span style={{ fontWeight: 600, fontSize: 14, color: COLORS.text }}>{comp.name}</span>
                {comp.file !== "—" && (
                  <span
                    style={{
                      fontSize: 10,
                      color: COLORS.textDim,
                      fontFamily: "monospace",
                      background: COLORS.card,
                      padding: "2px 8px",
                      borderRadius: 4,
                    }}
                  >
                    {comp.file}
                  </span>
                )}
              </div>
              <div style={{ fontSize: 12, color: COLORS.textMuted, marginTop: 6, lineHeight: 1.6 }}>
                {comp.detail}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function TruthLensArchitecture() {
  const [expandedLayers, setExpandedLayers] = useState(new Set(["capture"]));
  const [showAntiSpoof, setShowAntiSpoof] = useState(false);
  const [activeTab, setActiveTab] = useState("pipeline");

  const toggleLayer = (id) => {
    setExpandedLayers((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <div
      style={{
        background: COLORS.bg,
        color: COLORS.text,
        minHeight: "100vh",
        fontFamily: "'Inter', -apple-system, sans-serif",
        padding: 24,
        maxWidth: 800,
        margin: "0 auto",
      }}
    >
      {/* Header */}
      <div style={{ textAlign: "center", marginBottom: 32 }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 10 }}>
          <div
            style={{
              width: 40,
              height: 40,
              borderRadius: 10,
              background: `linear-gradient(135deg, ${COLORS.blue}, ${COLORS.purple})`,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 22,
            }}
          >
            🔍
          </div>
          <h1 style={{ fontSize: 28, fontWeight: 800, margin: 0, letterSpacing: -0.5 }}>
            TruthLens Architecture
          </h1>
        </div>
        <p style={{ color: COLORS.textMuted, fontSize: 14, marginTop: 8 }}>
          6-layer attestation pipeline — from camera shutter to immutable proof
        </p>
      </div>

      {/* Tab bar */}
      <div
        style={{
          display: "flex",
          gap: 4,
          background: COLORS.card,
          borderRadius: 10,
          padding: 4,
          marginBottom: 24,
        }}
      >
        {["pipeline", "anti-spoof", "file-map"].map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            style={{
              flex: 1,
              padding: "10px 16px",
              border: "none",
              borderRadius: 8,
              background: activeTab === tab ? COLORS.accent : "transparent",
              color: activeTab === tab ? COLORS.bg : COLORS.textMuted,
              fontWeight: activeTab === tab ? 700 : 500,
              fontSize: 13,
              cursor: "pointer",
              transition: "all 0.2s",
              textTransform: "capitalize",
            }}
          >
            {tab === "anti-spoof" ? "Anti-Spoofing" : tab === "file-map" ? "File Map" : "Pipeline"}
          </button>
        ))}
      </div>

      {/* Pipeline Tab */}
      {activeTab === "pipeline" && (
        <div>
          <div style={{ display: "flex", justifyContent: "flex-end", marginBottom: 12 }}>
            <button
              onClick={() => {
                if (expandedLayers.size === layers.length) {
                  setExpandedLayers(new Set());
                } else {
                  setExpandedLayers(new Set(layers.map((l) => l.id)));
                }
              }}
              style={{
                background: COLORS.card,
                border: `1px solid ${COLORS.border}`,
                color: COLORS.textMuted,
                padding: "6px 14px",
                borderRadius: 6,
                fontSize: 12,
                cursor: "pointer",
              }}
            >
              {expandedLayers.size === layers.length ? "Collapse All" : "Expand All"}
            </button>
          </div>
          {layers.map((layer) => (
            <LayerCard
              key={layer.id}
              layer={layer}
              isExpanded={expandedLayers.has(layer.id)}
              onToggle={() => toggleLayer(layer.id)}
            />
          ))}

          {/* Data flow */}
          <div
            style={{
              background: COLORS.card,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              padding: 20,
              marginTop: 20,
            }}
          >
            <h3 style={{ fontSize: 14, fontWeight: 700, marginTop: 0, color: COLORS.accent }}>
              DATA FLOW SUMMARY
            </h3>
            <div style={{ fontFamily: "monospace", fontSize: 12, lineHeight: 2.2, color: COLORS.textMuted }}>
              <div>
                <span style={{ color: COLORS.blue }}>Camera Shutter</span> →{" "}
                <span style={{ color: COLORS.textDim }}>raw bytes + 10 sensor readings</span>
              </div>
              <div>
                → <span style={{ color: COLORS.green }}>SHA-256 hash</span> →{" "}
                <span style={{ color: COLORS.green }}>canonical JSON payload</span> →{" "}
                <span style={{ color: COLORS.green }}>Ed25519 signature</span>
              </div>
              <div>
                → <span style={{ color: COLORS.accent }}>hash sent to TSA</span> →{" "}
                <span style={{ color: COLORS.accent }}>RFC 3161 token returned</span>
              </div>
              <div>
                → <span style={{ color: COLORS.purple }}>hash into Merkle tree</span> →{" "}
                <span style={{ color: COLORS.purple }}>root anchored on Polygon</span>
              </div>
              <div>
                → <span style={{ color: COLORS.cyan }}>C2PA manifest generated</span> →{" "}
                <span style={{ color: COLORS.cyan }}>attached to media file</span>
              </div>
              <div>
                → <span style={{ color: COLORS.red }}>ProofRecord stored locally</span> →{" "}
                <span style={{ color: COLORS.green }}>Trust Score computed</span> ✓
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Anti-Spoofing Tab */}
      {activeTab === "anti-spoof" && (
        <div>
          <div
            style={{
              background: COLORS.card,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              padding: 20,
              marginBottom: 16,
            }}
          >
            <h3 style={{ fontSize: 14, fontWeight: 700, marginTop: 0, color: COLORS.accent }}>
              WHY MULTI-SIGNAL MATTERS
            </h3>
            <p style={{ fontSize: 13, color: COLORS.textMuted, lineHeight: 1.7 }}>
              Any single signal can be faked. GPS spoofing apps exist. Device clocks can be changed.
              VPNs mask IP addresses. TruthLens captures 10+ independent signals simultaneously and
              cross-references them. Faking all of them consistently in real-time is exponentially harder
              than faking any one.
            </p>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {antiSpoofing.map((item, i) => (
              <div
                key={i}
                style={{
                  background: i === antiSpoofing.length - 1 ? "#1a2920" : COLORS.card,
                  border: `1px solid ${i === antiSpoofing.length - 1 ? COLORS.green : COLORS.border}`,
                  borderRadius: 10,
                  padding: 16,
                }}
              >
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <span style={{ fontWeight: 600, fontSize: 14, color: COLORS.text }}>{item.signal}</span>
                  <span
                    style={{
                      fontSize: 11,
                      padding: "3px 10px",
                      borderRadius: 20,
                      fontWeight: 600,
                      background:
                        item.fake.startsWith("Easy")
                          ? "#3b1a1a"
                          : item.fake.startsWith("Moderate")
                          ? "#3b2e1a"
                          : item.fake.startsWith("Hard")
                          ? "#1a2e3b"
                          : item.fake.startsWith("Very")
                          ? "#1a3b20"
                          : "#0d3b1a",
                      color:
                        item.fake.startsWith("Easy")
                          ? COLORS.red
                          : item.fake.startsWith("Moderate")
                          ? COLORS.accent
                          : item.fake.startsWith("Hard")
                          ? COLORS.blue
                          : item.fake.startsWith("Very")
                          ? COLORS.cyan
                          : COLORS.green,
                    }}
                  >
                    Fake: {item.fake}
                  </span>
                </div>
                <div style={{ fontSize: 12, color: COLORS.textMuted, marginTop: 6 }}>
                  {item.crossCheck}
                </div>
              </div>
            ))}
          </div>

          {/* Trust score breakdown */}
          <div
            style={{
              background: COLORS.card,
              border: `1px solid ${COLORS.border}`,
              borderRadius: 12,
              padding: 20,
              marginTop: 16,
            }}
          >
            <h3 style={{ fontSize: 14, fontWeight: 700, marginTop: 0, color: COLORS.accent }}>
              TRUST SCORE BREAKDOWN
            </h3>
            {[
              { label: "Ed25519 Signature", points: 20, color: COLORS.green },
              { label: "RFC 3161 Timestamp", points: 25, color: COLORS.accent },
              { label: "Blockchain Anchor", points: 25, color: COLORS.purple },
              { label: "C2PA Manifest", points: 15, color: COLORS.cyan },
              { label: "GPS Location", points: 10, color: COLORS.blue },
              { label: "NTP Verification", points: 5, color: COLORS.textMuted },
            ].map((item, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 10 }}>
                <div style={{ width: 50, textAlign: "right", fontSize: 18, fontWeight: 700, color: item.color }}>
                  +{item.points}
                </div>
                <div style={{ flex: 1, height: 8, background: COLORS.bg, borderRadius: 4, overflow: "hidden" }}>
                  <div
                    style={{
                      width: `${item.points}%`,
                      height: "100%",
                      background: item.color,
                      borderRadius: 4,
                    }}
                  />
                </div>
                <div style={{ fontSize: 13, color: COLORS.textMuted, minWidth: 140 }}>{item.label}</div>
              </div>
            ))}
            <div
              style={{
                borderTop: `1px solid ${COLORS.border}`,
                paddingTop: 10,
                marginTop: 8,
                display: "flex",
                justifyContent: "space-between",
              }}
            >
              <span style={{ fontSize: 14, fontWeight: 700, color: COLORS.green }}>= 100 Maximum Trust</span>
              <span style={{ fontSize: 11, color: COLORS.textDim }}>90+ Max | 70+ High | 45+ Mod | &lt;45 Basic</span>
            </div>
          </div>
        </div>
      )}

      {/* File Map Tab */}
      {activeTab === "file-map" && (
        <div>
          {[
            {
              folder: "lib/core/crypto/",
              color: COLORS.green,
              files: [
                { name: "key_manager.dart", desc: "Ed25519 keypair generation, Secure Enclave storage, sign/verify ops" },
                { name: "proof_signer.dart", desc: "Full signing pipeline orchestrator, canonical JSON builder" },
                { name: "timestamp_authority.dart", desc: "RFC 3161 TSA client, ASN.1 DER encoding, multi-server fallback" },
              ],
            },
            {
              folder: "lib/core/blockchain/",
              color: COLORS.purple,
              files: [
                { name: "blockchain_anchor.dart", desc: "EVM chain support, Merkle tree batching, proof verification" },
              ],
            },
            {
              folder: "lib/core/c2pa/",
              color: COLORS.cyan,
              files: [
                { name: "c2pa_manifest.dart", desc: "C2PA 2.0 manifest builder, 5 assertion types, claim signing" },
              ],
            },
            {
              folder: "lib/models/",
              color: COLORS.accent,
              files: [
                { name: "capture_metadata.dart", desc: "10+ sensor fields, GPS, EXIF, network, device info" },
                { name: "proof_record.dart", desc: "Complete proof structure, trust score calculator, blockchain anchors" },
              ],
            },
            {
              folder: "lib/services/",
              color: COLORS.red,
              files: [
                { name: "capture_service.dart", desc: "Camera lifecycle, photo/video capture, metadata collection" },
                { name: "attestation_service.dart", desc: "Pipeline orchestrator, independent verification engine" },
                { name: "proof_storage_service.dart", desc: "Hive-based offline persistence, CRUD, export/backup" },
              ],
            },
            {
              folder: "lib/screens/",
              color: COLORS.blue,
              files: [
                { name: "capture/capture_screen.dart", desc: "Live camera preview, ticking UTC overlay, proof bottom sheet" },
                { name: "verify/verify_screen.dart", desc: "Verification UI, trust badge, check breakdown, QR scanner" },
                { name: "history/history_screen.dart", desc: "Proof timeline, thumbnails, status chips, export" },
                { name: "settings/settings_screen.dart", desc: "Identity display, capture/verification toggles, TSA config" },
              ],
            },
            {
              folder: "lib/widgets/",
              color: COLORS.textMuted,
              files: [
                { name: "trust_badge.dart", desc: "Circular score indicator with dynamic color ring" },
                { name: "proof_card.dart", desc: "5-layer attestation visualization with status indicators" },
              ],
            },
          ].map((group, gi) => (
            <div
              key={gi}
              style={{
                background: COLORS.card,
                border: `1px solid ${COLORS.border}`,
                borderRadius: 12,
                padding: 16,
                marginBottom: 10,
              }}
            >
              <div
                style={{
                  fontFamily: "monospace",
                  fontSize: 13,
                  fontWeight: 700,
                  color: group.color,
                  marginBottom: 10,
                }}
              >
                {group.folder}
              </div>
              {group.files.map((file, fi) => (
                <div
                  key={fi}
                  style={{
                    display: "flex",
                    gap: 12,
                    padding: "8px 0",
                    borderTop: fi > 0 ? `1px solid ${COLORS.border}` : "none",
                  }}
                >
                  <span style={{ fontFamily: "monospace", fontSize: 12, color: COLORS.text, minWidth: 220 }}>
                    {file.name}
                  </span>
                  <span style={{ fontSize: 12, color: COLORS.textDim }}>{file.desc}</span>
                </div>
              ))}
            </div>
          ))}

          <div
            style={{
              background: COLORS.card,
              border: `1px solid ${COLORS.green}`,
              borderRadius: 12,
              padding: 16,
              marginTop: 16,
              textAlign: "center",
            }}
          >
            <div style={{ fontSize: 32, fontWeight: 800, color: COLORS.green }}>17</div>
            <div style={{ fontSize: 13, color: COLORS.textMuted }}>Dart files — all fully implemented</div>
            <div style={{ fontSize: 12, color: COLORS.textDim, marginTop: 4 }}>
              + pubspec.yaml, README.md, .gitignore, LICENSE, analysis_options.yaml
            </div>
          </div>
        </div>
      )}

      {/* Footer */}
      <div style={{ textAlign: "center", marginTop: 32, color: COLORS.textDim, fontSize: 11 }}>
        TruthLens v1.0.0 — Flutter • Ed25519 • RFC 3161 • Polygon • C2PA 2.0
      </div>
    </div>
  );
}
