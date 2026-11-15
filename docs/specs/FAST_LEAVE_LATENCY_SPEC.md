# Specification: IGMP Fast-Leave Latency Measurement for IGMP Tester

## 1. Overview & Goal
Add **IGMP Leave Latency (Fast-Leave Verification)** to **IGMP Tester** (`tom-mcguire/igmp-tester`).

In live lighting and video networks, operators frequently switch universes, NDI feeds, or multicast presets on the fly. When a device leaves a multicast group, a properly configured AV switch with **IGMP Immediate-Leave (Fast-Leave)** enabled stops forwarding that multicast stream within milliseconds. If Fast-Leave is *disabled* (the default on many enterprise switches), the switch sends Group-Specific Queries and continues flooding the stream for **2,000–3,000 ms**, risking temporary link saturation when switching high-bitrate feeds.

This feature modifies the Receiver "Leave / Stop" lifecycle to measure the exact time elapsed between transmitting the `IGMP Leave` packet and the arrival of the final multicast datagram on the wire.

---

## 2. Measurement State Machine

When the user clicks **"Stop / Leave Group"** while actively receiving a stream:

```
[ ACTIVE RECEIVING ]
       │
       ▼ User clicks "Leave Group"
[ LEAVING / DRAINING (3.0s Window) ]
   1. Record T_leave = DateTime.now()
   2. Call socket.leaveMulticast(groupAddress) -> OS transmits IGMP Leave (0x17)
   3. Keep RawDatagramSocket bound & listening for up to 3,000 ms
   4. For each trailing packet arriving at T_pkt:
        • trailingPacketsCount++
        • T_lastPacket = T_pkt
   5. Close socket after 3,000 ms (or after 500 ms of silence once packets stop)
       │
       ▼
[ LEAVE REPORT COMPLETE ]
   • If trailingPacketsCount == 0: Leave Latency = < 1 ms (Immediate)
   • Else: Leave Latency = (T_lastPacket - T_leave).inMilliseconds
```

### Classification Thresholds
| Measured Leave Latency | Classification | Switch Behavior Interpretation |
| :--- | :--- | :--- |
| **`0 ms – 50 ms`** | **Fast-Leave Active** (Emerald Badge) | Switch immediately pruned the port upon receiving IGMP Leave (`0x17`). |
| **`51 ms – 500 ms`** | **Delayed Prune** (Amber Badge) | Switch pruned quickly, minor control-plane processing delay. |
| **`> 500 ms`** (typically `~2000–3000 ms`) | **Standard Query Timeout (No Fast-Leave)** (Crimson/Amber Badge) | Switch waited for Group-Specific Query (`2x Last Member Query Interval`) before stopping traffic. |

---

## 3. Architecture & Model Changes

```
lib/
├── data/
│   └── services/
│       └── multicast/
│           └── multicast_receiver_service.dart   <-- Implement post-leave drain window & timer
├── domain/
│   └── models/
│       └── multicast_stats.dart                  <-- Add LeaveLatencyResult model
└── ui/
    └── features/
        ├── dashboard/
        │   └── view_models/
        │       └── igmp_tester_view_model.dart   <-- Expose leaveMeasurementState & result
        └── receiver/
            └── views/
                └── receiver_panel.dart           <-- Render Leave Latency badge & trailing count
```

### 3.1 `LeaveLatencyResult` (`lib/domain/models/multicast_stats.dart`)
```dart
enum FastLeaveStatus {
  fastLeaveActive('Fast-Leave Active'),
  delayedPrune('Delayed Prune'),
  noFastLeave('No Fast-Leave (Query Timeout)'),
  inconclusive('No Traffic Before Leave');

  final String label;
  const FastLeaveStatus(this.label);
}

class LeaveLatencyResult {
  final String groupAddress;
  final int latencyMs;
  final int trailingPacketsReceived;
  final int trailingBytesReceived;
  final FastLeaveStatus status;
  final DateTime measuredAt;

  const LeaveLatencyResult({
    required this.groupAddress,
    required this.latencyMs,
    required this.trailingPacketsReceived,
    required this.trailingBytesReceived,
    required this.status,
    required this.measuredAt,
  });
}
```

---

## 4. UI & UX Specification

1. **Non-Blocking Drain Feedback (`ReceiverPanel`):**
   * When the user clicks **Stop / Leave**, the button transitions briefly to **`Measuring Leave...`** (with a 3-second progress indicator) while the socket drains trailing packets.
   * Clicking **Stop** a second time immediately aborts the drain window and closes the socket if the user doesn't want to wait.
2. **Leave Telemetry Pill (`ReceiverPanel`):**
   * Once complete, display a persistent diagnostic pill in the Receiver summary card:
     * **`⚡ Leave Stop Time: 6 ms (Fast-Leave Active • 1 trailing pkt)`** in emerald green, or
     * **`⏳ Leave Stop Time: 2,140 ms (No Fast-Leave • 94 trailing pkts)`** in amber with a tooltip explaining: *"Enable 'IGMP Immediate-Leave' on the switch port VLAN to prevent stream overlap during channel changes."*
3. **CSV Export Inclusion:**
   * Append `Last_Leave_Latency_Ms` and `Trailing_Packets_After_Leave` to the session export in `CsvExportService`.

---

## 5. Implementation Checklist for Agent
1. Add `LeaveLatencyResult` and `FastLeaveStatus` to `multicast_stats.dart`.
2. Update `MulticastReceiverService.stop()` to execute `leaveMulticast()` while keeping the socket open in a passive post-leave measurement state for up to 3,000 ms (early-exiting after 500 ms of silence once stream stops).
3. Track `trailingPacketsReceived` and compute exact `latencyMs` from `T_leave` to `T_lastPacket`.
4. Render the Leave Latency status badge in `ReceiverPanel` and include the metric in `CsvExportService`.
5. Add unit tests in `test/receiver_service_test.dart` simulating immediate stop vs. 2-second trailing packet flood.
