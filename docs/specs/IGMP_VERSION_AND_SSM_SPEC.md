# Specification: IGMPv2 / IGMPv3 Version & SSM Support for IGMP Tester

## 1. Overview & Goal
Add **IGMP Protocol Version Detection & Selection (`IGMPv2` / `IGMPv3` / `SSM`)** to **IGMP Tester** (`tom-mcguire/igmp-tester`).

Modern entertainment and broadcast networks frequently mix legacy lighting nodes (which speak **IGMPv2**) with newer AV-over-IP systems like AES67, Dante, NDI, or SMPTE ST 2110 (which rely on **IGMPv3** and Source-Specific Multicast `232.0.0.0/8`). If a managed switch's IGMP Snooping querier is locked to IGMPv3 while a client sends IGMPv2 joins (or vice versa), multicast group memberships can fail to register or drop silently.

This feature extends `IgmpQuerySniffer`, `MulticastReceiverService`, and the UI so technicians can see the exact IGMP version of incoming General Queries and explicitly test `IGMPv2`, `IGMPv3 (ASM)`, or `IGMPv3 (SSM)` joins.

---

## 2. Wire-Level Protocol Details

### 2.1 General Query Version Detection (`IgmpQuerySniffer`)
When `IgmpQuerySniffer` captures an IGMP Membership Query (`Type = 0x11`, destination `224.0.0.1`), determine the IGMP version directly from the IPv4 payload length and fields:

| IGMP Payload Length | Detected Version | Wire Structure |
| :--- | :--- | :--- |
| **8 Bytes** (with `Max Resp Code == 0x00`) | **IGMPv1** | Legacy RFC 1112 query (Max Resp Time unused) |
| **8 Bytes** (with `Max Resp Code > 0x00`) | **IGMPv2** | RFC 2236 query (`Max Resp Time` in 1/10s units) |
| **>= 12 Bytes** | **IGMPv3** | RFC 3376 query (includes `QQIC`, `QRV`, and `Number of Sources`) |

* **IGMPv3 Specific Fields to Parse:**
  * **Byte 8 (`Resv / S / QRV`):** Lower 3 bits give `QRV` (Querier's Robustness Variable, default `2`).
  * **Byte 9 (`QQIC`):** Querier's Query Interval Code (decodes to query interval in seconds, e.g., `125s`).
  * **Bytes 10–11:** Number of Source addresses (`N`).

### 2.2 Receiver Join Modes (`MulticastReceiverService`)
Extend `MulticastConfig` with an `IgmpJoinMode` option:
1. **`auto` (OS Default):** Standard `socket.joinMulticast(groupAddress)` using the OS stack's default IGMP version.
2. **`igmpv2`:** Forces IGMPv2 Membership Report (`0x16`) behavior (or raw socket IGMPv2 report emission when testing switch backward-compatibility).
3. **`igmpv3Asm`:** Standard Any-Source Multicast (`EXCLUDE {}`) IGMPv3 Membership Report (`0x22` to `224.0.0.22`).
4. **`igmpv3Ssm`:** Source-Specific Multicast (`INCLUDE {sourceIp}`) for `232.0.0.0/8` groups, requiring a `sourceFilterIp` field.

---

## 3. Architecture & Model Changes

```
lib/
├── data/
│   └── services/
│       ├── igmp/
│       │   └── igmp_query_sniffer.dart           <-- Parse v1/v2/v3 query headers & QQIC/QRV
│       └── multicast/
│           └── multicast_receiver_service.dart   <-- Support SSM source filtering & v2/v3 mode
├── domain/
│   └── models/
│       ├── igmp_query_event.dart                 <-- Add igmpVersion (1, 2, 3), qqicSeconds, qrv
│       └── multicast_config.dart                 <-- Add IgmpJoinMode & optional sourceIp
└── ui/
    └── features/
        ├── igmp_monitor/
        │   └── views/
        │       └── igmp_query_log_table.dart     <-- Display Version pill (IGMPv2 / IGMPv3) & QQIC
        └── receiver/
            └── views/
                └── receiver_panel.dart           <-- Add IGMP Mode dropdown & Source IP input (SSM)
```

### 3.1 `IgmpQueryEvent` Extensions
```dart
enum IgmpProtocolVersion { v1, v2, v3, unknown }

// Add to IgmpQueryEvent:
final IgmpProtocolVersion version;
final int? queryIntervalSeconds; // Decoded from QQIC in IGMPv3
final int? robustnessVariable;   // Decoded from QRV in IGMPv3
```

---

## 4. UI & Diagnostic Alert Rules

1. **`IgmpQueryLogTable` & `TopControlBar`:**
   * Update the Querier status pill in `TopControlBar` from `Querier: 10.201.100.1` to **`Querier: 10.201.100.1 (IGMPv3)`** or **`(IGMPv2)`**.
   * Show `Version`, `Max Resp Time`, and `Query Interval (QQIC)` columns in `IgmpQueryLogTable`.
2. **`ReceiverPanel` Controls:**
   * Add a compact dropdown: `[ IGMP Mode: Auto / IGMPv2 / IGMPv3 (SSM) ]`.
   * When `IGMPv3 (SSM)` is selected (or when the user enters a `232.x.x.x` address), reveal a **`Source IP`** input field to filter traffic strictly from that transmitter.
3. **Version Mismatch Warning (`GlobalErrorBanner`):**
   * If the user joins using `IGMPv3 (SSM)` (`232.x.x.x`) while the detected upstream Querier is only running **`IGMPv2`**, surface a clear warning: *"Upstream Querier (10.201.100.1) is running IGMPv2, which does not support Source-Specific Multicast (SSM)."*

---

## 5. Implementation Checklist for Agent
1. Update `IgmpQuerySniffer` to distinguish 8-byte IGMPv1/v2 queries from >= 12-byte IGMPv3 queries and decode `QQIC` / `QRV`.
2. Add `IgmpJoinMode` and `sourceFilterIp` to `MulticastConfig` and implement source-filtered socket subscription in `MulticastReceiverService`.
3. Update `TopControlBar` and `IgmpQueryLogTable` to display the detected IGMP version badge.
4. Add the `IGMP Mode` selector and conditional `Source IP` field to `ReceiverPanel`.
5. Add unit tests in `test/query_sniffer_test.dart` for IGMPv2 vs. IGMPv3 query packet parsing.
