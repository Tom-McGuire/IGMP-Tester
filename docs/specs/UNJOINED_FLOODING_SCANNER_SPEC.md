# Specification: Unjoined Multicast Flooding Scanner for IGMP Tester

## 1. Overview & Goal
Add an **"Unjoined / Flooding Traffic Scanner"** mode to **IGMP Tester** (`tom-mcguire/igmp-tester`).

A classic troubleshooting blind spot occurs when IGMP Snooping is misconfigured or disabled on a switch, or when a multicast transmitter is sending to an unregistered/flooded range (e.g., `224.0.0.x` link-local or poorly configured Art-Net/sACN universes). When this happens, multicast streams flood onto your laptop's NIC **even though your application never sent an IGMP Join**. Conversely, technicians often plug into an unfamiliar network and want to see which multicast universes/streams are already bleeding onto their port without blindly guessing IP addresses.

This feature adds a **"Passive Port Scan (No IGMP Join)"** mode to the Receiver that binds a UDP listener *without* calling `joinMulticast()`, catalogs every leaking/flooding multicast stream hitting the NIC, and lets the user **"Adopt & Track"** any discovered stream with one click.

---

## 2. How Passive Flooding Detection Works

1. **Bind Without Membership Report:**
   * `MulticastReceiverService` binds a `RawDatagramSocket` to `InternetAddress.anyIPv4` (`0.0.0.0`) on target AV ports (configurable: default `5568` sACN/ACN, `6454` Art-Net, `4321` / `5004` Dante/RTP, or a custom port) with `reuseAddress: true`.
   * Crucially, it **does not call `socket.joinMulticast()`**, ensuring the OS sends **zero** IGMP Membership Reports onto the wire.
2. **Destination Group Extraction:**
   * Using packet metadata and socket headers, inspect the destination multicast IPv4 address (`224.0.0.0/4`) and source unicast IP of every incoming datagram.
3. **Stream Classification & Snooping Verdict:**
   * Any non-control multicast stream (`!= 224.0.0.1` / `224.0.0.22` / `224.0.0.251` mDNS) arriving on the port without an active IGMP Join proves that **unregistered multicast flooding** is occurring on that switch port.

---

## 3. Architecture & Domain Models

```
lib/
├── data/
│   └── services/
│       └── multicast/
│           └── flooding_scanner_service.dart     <-- [NEW] Binds UDP ports without IGMP Join
├── domain/
│   └── models/
│       └── flooded_stream_entry.dart             <-- [NEW] Discovered unjoined stream metadata
└── ui/
    └── features/
        ├── dashboard/
        │   └── view_models/
        │       └── igmp_tester_view_model.dart   <-- Manage passive scan state & adopt action
        └── receiver/
            └── views/
                ├── receiver_panel.dart           <-- Add [Scan Unjoined Traffic] button
                └── flooded_streams_sheet.dart    <-- [NEW] Live table of leaking streams + Adopt
```

### 3.1 `FloodedStreamEntry` (`lib/domain/models/flooded_stream_entry.dart`)
```dart
class FloodedStreamEntry {
  final String multicastGroup; // e.g., "239.255.0.12"
  final int port;              // e.g., 5568
  final String sourceIp;       // e.g., "10.201.100.101"
  final String detectedProtocol; // e.g., "sACN (Univ 12)", "Art-Net", "Dante/RTP", "Unknown UDP"
  final int packetsSeen;
  final double bitrateKbps;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const FloodedStreamEntry({
    required this.multicastGroup,
    required this.port,
    required this.sourceIp,
    required this.detectedProtocol,
    required this.packetsSeen,
    required this.bitrateKbps,
    required this.firstSeen,
    required this.lastSeen,
  });
}
```

### 3.2 Lightweight Header Identification
When a flooded packet arrives on the unjoined socket, inspect the first 16 bytes to label the stream automatically:
* **`5568` + `"ASC-E1.17"`:** Label as `sACN (Universe X)` (extracting the 16-bit universe ID at payload bytes `113–114`) or `ACN E1.17`.
* **`6454` + `"Art-Net\0"`:** Label as `Art-Net (Universe X)` (extracting `SubUni` / `Net` at bytes `14–15`).
* **`4321` / `5004` + `0x80` RTP header:** Label as `Dante / AES67 RTP`.

---

## 4. UI & User Workflow

1. **Trigger Button (`ReceiverPanel`):**
   * Add a secondary action button next to `Start Receiver`: **`🔍 Scan Unjoined Traffic`**.
2. **Live Discovery Banner & Table (`FloodedStreamsSheet`):**
   * If **0 streams** arrive after 5 seconds: Display **`🟢 Port Clean: IGMP Snooping is actively blocking unjoined multicast traffic.`**
   * If **>= 1 streams** arrive: Display an amber alert banner: **`⚠ Unregistered Multicast Flooding Detected (X Streams)`** and populate a live table showing Group, Port, Protocol, Source IP, and Rate.
3. **"Adopt & Track" Action:**
   * Clicking **`Adopt & Track`** stops the passive scan, auto-populates `MulticastConfig` with that stream's `multicastGroup` and `port`, sends a proper IGMP Join, and immediately begins sequence gap analysis.

---

## 5. Implementation Checklist for Agent
1. Create `FloodedStreamEntry` model in `lib/domain/models/flooded_stream_entry.dart`.
2. Build `FloodingScannerService` to bind common AV UDP ports (`5568`, `6454`, `4321`, `5004`) without calling `joinMulticast()`, grouping packets by `(sourceIp, multicastGroup, port)`.
3. Add protocol signature & sACN/Art-Net universe number extraction for discovered streams.
4. Add the `🔍 Scan Unjoined Traffic` trigger and `FloodedStreamsSheet` UI with one-click `Adopt & Track` handoff to `IgmpTesterViewModel`.
5. Add unit tests verifying packet grouping and sACN/Art-Net universe label extraction.
