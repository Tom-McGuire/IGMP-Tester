# Specification: DSCP / QoS Tag Injection & Verification for IGMP Tester

## 1. Overview & Goal
Add **DiffServ (DSCP) QoS Priority Tagging & Transit Verification** to **IGMP Tester** (`tom-mcguire/igmp-tester`).

In converged AV networks carrying Dante/AES67 audio alongside sACN lighting and NDI video, switches rely on **IPv4 DSCP (Differentiated Services Code Point)** tags to place PTP clock sync and audio packets into strict-priority hardware queues:
* **DSCP 46 (`EF` — Expedited Forwarding):** PTPv2 Sync/Follow-Up messages.
* **DSCP 34 (`AF41` — Assured Forwarding):** Dante / AES67 real-time audio flows.
* **DSCP 0 (`BE` — Best Effort):** Standard bulk data / unprioritized lighting or video.

A common network fault occurs when a misconfigured switch port or router resets incoming DSCP markings back to `0` (`Best Effort`), causing audio glitches whenever a large sACN or NDI burst crosses the same trunk. This feature allows the **Sender** to stamp synthetic test streams with a chosen DSCP value and enables the **Receiver** to inspect the incoming IPv4 `TOS / DSCP` byte to verify whether QoS tags survived transit intact.

---

## 2. DSCP Presets & IPv4 Header Mapping

The 6-bit DSCP value occupies the upper 6 bits of the 8-bit IPv4 **Type of Service (TOS) / Traffic Class** byte (`TOS = DSCP << 2`):

| Preset Name | DSCP Decimal | DSCP Name | IPv4 TOS Byte (`DSCP << 2`) | Typical AV Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **Best Effort (Default)** | `0` | `BE / CS0` | `0x00` (`0`) | Standard unprioritized traffic |
| **sACN / Control Priority** | `24` | `CS3` | `0x60` (`96`) | Lighting & show control prioritization |
| **Dante / AES67 Audio** | `34` | `AF41` | `0x88` (`136`) | Real-time multicast audio streams |
| **PTP Clock / Voice** | `46` | `EF` | `0xB8` (`184`) | IEEE 1588 PTPv2 timing synchronization |
| **Network Control** | `56` | `CS7` | `0xE0` (`224`) | Switch control / high-priority telemetry |

---

## 3. Architecture & Model Changes

```
lib/
├── data/
│   └── services/
│       └── multicast/
│           ├── multicast_sender_service.dart     <-- Set IP_TOS socket option before sending
│           └── multicast_receiver_service.dart   <-- Read incoming IP_TOS / IP_RECVTOS metadata
├── domain/
│   └── models/
│       ├── dscp_preset.dart                      <-- [NEW] DSCP enum, TOS byte math & labels
│       ├── multicast_config.dart                 <-- Add DscpPreset txDscp & expectedRxDscp
│       └── multicast_stats.dart                  <-- Add observedDscp & bool isDscpStripped
└── ui/
    └── features/
        ├── sender/
        │   └── views/
        │       └── sender_panel.dart             <-- Add DSCP Priority dropdown selector
        └── receiver/
            └── views/
                └── receiver_panel.dart           <-- Display Observed DSCP badge & Strip Alert
```

### 3.1 `DscpPreset` (`lib/domain/models/dscp_preset.dart`)
```dart
enum DscpPreset {
  bestEffort(0, 'BE (0)', 'Best Effort'),
  cs3Control(24, 'CS3 (24)', 'Show Control'),
  af41Audio(34, 'AF41 (34)', 'Dante / AES67 Audio'),
  efPtp(46, 'EF (46)', 'PTP Clock / Expedited'),
  cs7Network(56, 'CS7 (56)', 'Network Control');

  final int dscpValue;
  final String shortLabel;
  final String description;
  const DscpPreset(this.dscpValue, this.shortLabel, this.description);

  int get tosByte => (dscpValue & 0x3F) << 2;

  static DscpPreset? fromTosByte(int tosByte) {
    final dscp = (tosByte >> 2) & 0x3F;
    for (final preset in values) {
      if (preset.dscpValue == dscp) return preset;
    }
    return null;
  }

  static int extractDscpFromTos(int tosByte) => (tosByte >> 2) & 0x3F;
}
```

### 3.2 Socket Level TOS Implementation (`dart:io`)
* **Sender (`MulticastSenderService`):**
  * Configure IPv4 `IP_TOS` via `RawSocketOption.fromInt` on the `RawDatagramSocket` before transmitting packets.
* **Receiver (`MulticastReceiverService`):**
  * Enable `IP_RECVTOS` on the receiving `RawDatagramSocket` so incoming datagram control messages expose the received IPv4 TOS byte.
  * Extract `observedDscp = (receivedTosByte >> 2) & 0x3F`.

---

## 4. UI & Diagnostic Alert Rules

1. **`SenderPanel` Selector:**
   * Add a compact **`QoS / DSCP Tag`** dropdown in the Sender configuration card:
     `[ BE (0) - Best Effort ]`, `[ CS3 (24) - Control ]`, `[ AF41 (34) - Dante Audio ]`, `[ EF (46) - PTP Clock ]`.
2. **`ReceiverPanel` QoS Verification Badge:**
   * Display the observed DSCP value of incoming traffic in real time:
     * **When DSCP > 0:** Render a cyan/emerald badge: **`🏷 QoS: DSCP 34 (AF41) — Preserved`**.
     * **When DSCP Stripping is Detected:** Highlight badge in crimson/amber: **`⚠ QoS Stripped: Expected DSCP 34 (AF41), Received DSCP 0 (BE)`**.
3. **Diagnostic Guidance (`GlobalErrorBanner`):**
   * *"QoS Policy Alert: Incoming packets arrived with DSCP 0 (Best Effort). An upstream switch or router is remarking/stripping DiffServ tags."*

---

## 5. Implementation Checklist for Agent
1. Create `DscpPreset` enum and TOS byte conversion helpers in `lib/domain/models/dscp_preset.dart`.
2. Update `MulticastConfig` and `MulticastStats` with `txDscp`, `observedDscp`, and `dscpRemarked` flags.
3. Apply `IP_TOS` socket option in `MulticastSenderService`.
4. Enable `IP_RECVTOS` in `MulticastReceiverService` to extract the received IPv4 TOS byte and compute `observedDscp`.
5. Add the DSCP selector to `SenderPanel` and the live QoS verification / stripping warning badge to `ReceiverPanel`.
6. Add unit tests verifying `tosByte` encoding/decoding across all DSCP values (`0–63`).
