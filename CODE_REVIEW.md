# Comprehensive Project Audit & Code Review Report (`v0.5.6-Beta`)

This document provides an up-to-date audit of **IGMP & Multicast Tester** (`v0.5.6-Beta`), superseding the earlier pre-`v0.5.2` review (all items from the initial review were resolved in prior commits).

It is structured as an actionable engineering specification so implementation agents can systematically fix functional bugs, harden edge cases, refactor architectural bottlenecks, and remove unused code and dependencies.

---

## Priority 1: Functional Bugs & Runtime Errors

### 1.1. Crash When Adopting Non-sACN / Non-IGMPTEST Flooded Streams (`'Unknown Group'`)
- **Files:**
  - `lib/data/services/multicast/flooding_scanner_service.dart` (lines 558–595, 645–670)
  - `lib/ui/features/dashboard/view_models/igmp_tester_view_model.dart` (lines 652–698)
  - `lib/ui/features/receiver/views/flooded_streams_sheet.dart` (lines 938–960)
- **Root Cause:**
  1. `dart:io`'s `Datagram.address` contains the **sender's source IP**, not the destination multicast group IP.
  2. `FloodingScannerService._resolveGroupIp` only recovers the destination multicast IP for native `IGMPTEST` packets (from the 56-byte payload header) and `sACN` packets (computed from the 16-bit Universe ID at bytes `113..114`). For **Art-Net**, **Dante / AES67 RTP** (ports `5004`, `4321`), and **Unknown UDP**, `_resolveGroupIp` returns `'Unknown Group'`.
  3. Clicking **"Adopt & Track"** on any stream with `groupIp == 'Unknown Group'` passes `'Unknown Group'` into `IgmpTesterViewModel.adoptFloodedStream`, which adds a receiver stream with `groupAddress: 'Unknown Group'` and calls `_receiverService.startStream(...)`. `InternetAddress('Unknown Group')` (line 358 of `multicast_receiver_service.dart`) throws an `ArgumentError` (`Invalid internet address Unknown Group`) and leaves a broken stream config in the Receiver table.
  4. Additionally, in `_processDatagram` (lines 581–587), `_ignoreUnicast` checks `_parseIpv4Octets(resolvedGroup) != null && !isMulticastIpv4(resolvedGroup)`. When a unicast UDP packet (e.g., unicast Art-Net or random unicast UDP traffic) hits a scanned port, `resolvedGroup` is `'Unknown Group'`, `_parseIpv4Octets` returns `null`, and the unicast filter is bypassed—falsely triggering the red `"Unregistered Multicast Flooding Detected"` alert banner.
- **Required Fix:**
  - Add a `bool get hasValidMulticastGroup => FloodingScannerService.isMulticastIpv4(groupIp);` getter on `FloodedStreamEntry`.
  - In `FloodedStreamsSheet._buildAdoptButton`, if `!entry.hasValidMulticastGroup`, either disable quick-adopt or prompt the user for the multicast group IP (or pre-fill a valid default group from the detected protocol preset, e.g., `239.69.1.1` for Dante/RTP or `239.255.0.1` for Art-Net) before calling `onAdoptStream`.
  - In `IgmpTesterViewModel.adoptFloodedStream`, validate `MulticastStreamConfig.isValidMulticastIpv4(entry.groupIp)` before adding or starting the stream; if invalid, set `_errorMessage` and return early.

---

### 1.2. `IgmpQuerierWatchdog` Permanently Stops Ticking After `stopAll()`
- **Files:**
  - `lib/ui/features/dashboard/view_models/igmp_tester_view_model.dart` (lines 299, 734–752, 791–814, 936–943)
- **Root Cause:**
  - `IgmpTesterViewModel.init()` starts the 1-second periodic watchdog timer via `_watchdog.start()` (line 299).
  - When the user clicks **"Stop All"** in `TopControlBar` (or when `stopAll()` is invoked), line 941 calls `_watchdog.stop()`, canceling `_watchdog._timer`.
  - Neither `startAll()`, `toggleSniffer()`, nor `startDemoWalkthrough()` ever calls `_watchdog.start()` again. Consequently, after clicking "Stop All" once, `secondsSinceLastQuery` freezes and querier health (`active` -> `warning` -> `critical`) never updates or expires for the rest of the application session.
- **Required Fix:**
  - Call `_watchdog.start()` inside `toggleSniffer()` when starting the sniffer, inside `startAll()`, and inside `startDemoWalkthrough()` (or keep `_watchdog` running and use `_watchdog.reset()` in `stopAll()` rather than permanently killing its timer).

---

### 1.3. Inaccurate Transmitter Packet Pacing for Non-Divisors of 100 PPS (`MulticastSenderService`)
- **File:** `lib/data/services/multicast/multicast_sender_service.dart` (lines 127–156)
- **Root Cause:**
  - The sender pacing logic computes:
    ```dart
    if (pps <= 50) {
      tickMs = (1000 / pps).round().clamp(10, 1000);
      packetsPerTick = 1;
    } else {
      tickMs = 10;
      packetsPerTick = (pps / 100).ceil();
    }
    ```
  - Because `packetsPerTick = (pps / 100).ceil()` rounds up to an integer per 10 ms tick:
    - Any rate in `51..99 pps` (e.g., `60 pps`) sets `tickMs = 10, packetsPerTick = 1`, transmitting at **`100 pps`** (+67% error).
    - Any rate in `101..199 pps` (e.g., `128 pps` PTP preset) sets `tickMs = 10, packetsPerTick = 2`, transmitting at **`200 pps`** (+56% error).
    - Rates like `44 pps` (sACN preset) round `1000 / 44` to `23 ms`, and on Windows (where default timer resolution is ~15.6 ms), `Timer.periodic` drifts by 25–30%.
  - Furthermore, inside the burst loop (lines 141–148), `nowUs` is sampled once outside the `for` loop, stamping every packet in a multi-packet tick with an identical `sendTimestampUs`.
- **Required Fix:**
  - Replace the naive `packetsPerTick = (pps / 100).ceil()` calculation with an elapsed-time accumulator in the periodic callback:
    - Compute `elapsedUs = nowUs - context.startTime.microsecondsSinceEpoch`.
    - Compute `targetPackets = ((elapsedUs * pps) ~/ 1000000).clamp(context.packetsSent, context.packetsSent + maxBurstPerTick)`.
    - Send `targetPackets - context.packetsSent` packets on that tick.
  - Refresh `DateTime.now().microsecondsSinceEpoch` (or increment by `intervalUs`) per packet in the burst loop so receiver RFC 3550 jitter calculations are not skewed by zero-delta burst timestamps.

---

### 1.4. Live Socket DSCP / TOS Verification Always Remains `unverified` (`MulticastReceiverService`)
- **Files:**
  - `lib/data/services/multicast/multicast_receiver_service.dart` (lines 234, 238–246, 554–559, 637–653)
  - `lib/data/services/multicast/dscp_socket_helper.dart` (lines 57–63)
- **Root Cause:**
  - In `_ensurePooledSocket` (line 243), the live socket listener calls `_processDatagram(datagram, port)` without passing `receivedTosByte` because `dart:io`'s `RawDatagramSocket.receive()` returns a `Datagram` without `recvmsg` ancillary control headers (`IP_RECVTOS` `cmsg`).
  - In `_processDatagram` (lines 638–652), `ctx.dscpTransitStatus` is **only** evaluated inside `if (receivedTosByte != null)`.
  - As a result, `receivedTosByte` is only non-null when injected via `processDatagramForTesting`. In real network operation:
    1. `ctx.lastReceivedDscp` and `ctx.dscpTransitStatus` remain permanently `null` / `DscpTransitStatus.unverified`.
    2. Even when the user explicitly sets an `expectedDscp` on a receiver group (e.g., `EF (46)`) and the transmitter sends packets tagged with a different DSCP in the `MulticastPacket` header (`packet.encodedDscp`, e.g., `BE (0)` or `AF41 (34)`), no mismatch alert is raised.
- **Required Fix:**
  - When `receivedTosByte == null` (standard `dart:io` socket receive) but `ctx.config.expectedDscp != null` and `hintDscp != null` (`packet.encodedDscp`), evaluate or surface mismatches between `ctx.config.expectedDscp!.dscpValue` and `hintDscp` (or clearly label in-band sender DSCP tag vs. OS TOS).

---

### 1.5. Fast-Leave Measurement Reports `0 ms (Fast-Leave Active)` on Idle / Dead Streams
- **Files:**
  - `lib/data/services/multicast/multicast_receiver_service.dart` (lines 825–871, 906–945)
  - `lib/domain/models/multicast_stats.dart` (lines 4–30)
  - `docs/specs/FAST_LEAVE_LATENCY_SPEC.md` (lines 67–75)
- **Root Cause:**
  - If a user joins a multicast group where **no traffic is arriving** (`ctx.packetsReceived == 0` or no packets arrived recently before leave) and clicks Stop/Leave with **Fast-Leave Probe** enabled, `drainCtx.lastPacketReceivedAt` remains `null`.
  - When the 500 ms `silenceTimer` fires, `_completeDrain` (lines 915–916) evaluates `drainCtx.lastPacketReceivedAt == null ? FastLeaveStatus.fastLeaveActive : ...` and reports **`0 ms — Fast-Leave Active`**.
  - Leaving a group that never received traffic cannot verify switch Fast-Leave behavior and gives a false-positive green pass.
- **Required Fix:**
  - Record whether the stream was actively receiving packets prior to leave (e.g., `ctx.packetsReceived > 0` and last packet arrived within the last few seconds). If no traffic was flowing prior to leave and `trailingPacketsReceived == 0`, classify the result as `FastLeaveStatus.inconclusive` (as defined in `docs/specs/FAST_LEAVE_LATENCY_SPEC.md`) or `FastLeaveStatus.notMeasured`.

---

### 1.6. SSM + ASM Membership Leak on Shared Pooled Socket (`_dropMulticastMembership`)
- **File:** `lib/data/services/multicast/multicast_receiver_service.dart` (lines 373–437, 738–784)
- **Root Cause:**
  - When an SSM stream (`stream A`) succeeds with OS `IP_ADD_SOURCE_MEMBERSHIP`, its membership is recorded in `pooled.joinedSsmKeys` (not `pooled.joinedGroups`).
  - If an ASM stream (`stream B`) on the same `(groupAddress, port)` shares the same `_PooledSocket`, its membership is recorded in `pooled.joinedGroups`.
  - When `stream B` (ASM) is stopped while `stream A` (SSM) remains active, `_dropMulticastMembership` checks:
    ```dart
    final groupStillUsed = _streams.values.any(
      (s) => s.pooledSocket == pooled && s.isJoined && s.config.groupAddress == ctx.config.groupAddress,
    );
    ```
    Because `stream A` matches `s.config.groupAddress == ctx.config.groupAddress`, `groupStillUsed` is `true`, so `leaveMulticast` is **never called** for `stream B`'s `(*, G)` ASM join, keeping the socket subscribed to all sources `(*, G)` and defeating `stream A`'s `(S, G)` filter!
- **Required Fix:**
  - In `_dropMulticastMembership` (line 769), only count remaining streams that actually rely on `joinedGroups` (`!s.ssmOsFilterApplied`):
    ```dart
    final groupStillUsed = _streams.values.any(
      (s) =>
          s.pooledSocket == pooled &&
          s.isJoined &&
          !s.ssmOsFilterApplied &&
          s.config.groupAddress == ctx.config.groupAddress,
    );
    ```

---

## Priority 2: Resource Leaks, Performance & Platform Issues

### 2.1. Undisposed `TextEditingController` & Missing Input Feedback in `_showPassivePortDialog`
- **File:** `lib/ui/features/receiver/views/receiver_panel.dart` (lines 58–118)
- **Issue:**
  - `_showPassivePortDialog` creates `final ctrl = TextEditingController(...)` inside a stateless method and never disposes it when the dialog closes.
  - Clicking **"Save Port"** with an out-of-range or non-numeric port (e.g., `0`, `70000`, `abc`) silently does nothing without displaying an inline validation message.
- **Required Fix:**
  - Extract the dialog into a dedicated `_PassivePortDialog extends StatefulWidget` that disposes its `TextEditingController` in `dispose()` and displays an inline `_errorText` when the port is not in `1..65535`.

---

### 2.2. Synchronous SQLite Queries & File I/O on Main UI Isolate (`SuiteThemeSyncService`)
- **File:** `lib/data/services/storage/suite_theme_sync_service.dart` (lines 19–84)
- **Issue:**
  - `getThemeMode()` returns `Future<String>`, but executes synchronous `File(targetPath).existsSync()`, `sqlite3.open(...)`, `db.execute('PRAGMA busy_timeout = 1000;')`, and `db.select(...)` on the main UI isolate. If another Network Suite app is writing to `shared_devices.db`, `busy_timeout = 1000` can stall the UI thread for up to 1 second.
  - `watchExternalChanges()` listens to `dir.watch()` without debouncing. A single SQLite transaction emits multiple filesystem events (`shared_devices.db-wal`, `shared_devices.db-shm`, `shared_devices.db`), triggering back-to-back synchronous SQLite opens on the main isolate.
- **Required Fix:**
  - Debounce events in `watchExternalChanges()` (e.g., 100–150 ms) or run the read-only SQLite check via `Isolate.run(...)` with a short `busy_timeout` (e.g., `100 ms`).

---

### 2.3. Unbounded Memory Growth in Passive / Flooding Stream Maps
- **Files:**
  - `lib/data/services/multicast/multicast_receiver_service.dart` (lines 158, 495–537)
  - `lib/data/services/multicast/flooding_scanner_service.dart` (lines 54, 597–640)
- **Issue:**
  - While `_allGaps` (`maxRetainedGaps = 5000`) and `IgmpQuerySnifferService._events` (`1000`) are capped, `MulticastReceiverService._unsubscribedContexts` and `FloodingScannerService._entriesByKey` have no size limit.
  - Flooded traffic with spoofed or varying source IPs / group addresses will insert new map keys indefinitely.
- **Required Fix:**
  - Cap `_unsubscribedContexts` and `_entriesByKey` (e.g., `maxTrackedStreams = 500`), evicting the oldest-seen entry when full.

---

### 2.4. Hardcoded `/24` Subnet Mask in `NetworkInterfaceService`
- **Files:**
  - `lib/data/services/network/network_interface_service.dart` (lines 16–26)
  - `lib/domain/models/network_interface_info.dart` (lines 16–20)
  - `lib/ui/features/dashboard/views/dialogs/device_library_dialog.dart` (line 372)
- **Issue:**
  - `NetworkInterfaceService.getAvailableInterfaces()` hardcodes `subnetMask: '255.255.255.0'` and `prefixLength: 24` for every interface, and never calls `NetworkInterfaceInfo.prefixToSubnetMask(int prefix)`.
  - As a result, `DeviceLibraryDialog` displays `Subnet: 255.255.255.0` even for loopback (`127.0.0.1`, `/8`), link-local (`169.254.x.x`, `/16`), or enterprise `/16` / `/23` interfaces.
- **Required Fix:**
  - Infer sensible default prefix lengths when `dart:io` does not expose netmask directly (e.g., `8` for `127.x.x.x`, `16` for `169.254.x.x`, or query OS netmask) and compute `subnetMask` via `NetworkInterfaceInfo.prefixToSubnetMask(prefixLength)`, or omit misleading hardcoded `/24` mask display when unknown.

---

### 2.5. Deprecated & Silently Ignored `socket.multicastInterface` on Sender Sockets
- **File:** `lib/data/services/multicast/multicast_sender_service.dart` (lines 71–76)
- **Issue:**
  - `socket.multicastInterface = rawInterface;` uses a deprecated `dart:io` API (`// ignore: deprecated_member_use`) wrapped in `try { ... } catch (_) {}`.
  - On Windows and Linux, `RawDatagramSocket.multicastInterface=` is unimplemented or throws in Dart's standard library, so the exception is silently swallowed and outbound multicast packets egress via the OS default route rather than the selected NIC.
- **Required Fix:**
  - Bind the sender socket directly to the selected interface's IPv4 unicast address (`InternetAddress(selectedInterface.ip)`) instead of `InternetAddress.anyIPv4` when a specific interface is selected, or set `IP_MULTICAST_IF` (`option 32` on Linux/macOS, `option 9` on Windows) via `RawSocketOption` on `IPPROTO_IP`, falling back to `anyIPv4` if binding fails.

---

### 2.6. macOS App Sandbox Prevents Executing External `tshark` Binary
- **Files:**
  - `macos/Runner/Release.entitlements`
  - `macos/Runner/DebugProfile.entitlements`
- **Issue:**
  - Both entitlement files have `<key>com.apple.security.app-sandbox</key><true/>`. While network client/server entitlements are present, the macOS App Sandbox blocks spawning external binaries such as `/opt/homebrew/bin/tshark`, `/usr/local/bin/tshark`, and `/usr/bin/which` via `Process.start` / `Process.run`.
- **Required Fix:**
  - Since this desktop utility is distributed outside the Mac App Store (per `README.md`) and requires executing system `tshark`, set `<key>com.apple.security.app-sandbox</key><false/>` in `Release.entitlements` and `DebugProfile.entitlements`.

---

### 2.7. Unhandled Exception in `GapAnalysisTable._exportCsv`
- **File:** `lib/ui/features/gaps/views/gap_analysis_table.dart` (lines 28–49)
- **Issue:**
  - Unlike `TopControlBar` (lines 272–298), `GapAnalysisTable._exportCsv` does not wrap `FilePicker.saveFile(...)` in a `try / catch` block. If the file picker throws a platform exception or write permission error, it results in an unhandled async exception.
- **Required Fix:**
  - Unify the CSV export UI workflow into a shared helper method (or ViewModel/dialog helper) with proper `try / catch` and error `SnackBar` feedback.

---

## Priority 3: Unused Code, Dead Symbols & Dependency Cleanup

### 3.1. Unused Production Classes, Enums, Getters & Methods
The following symbols in `lib/` are dead or never used in production code:

| File | Lines | Symbol | Status / Action |
| :--- | :--- | :--- | :--- |
| `lib/domain/models/multicast_config.dart` | 19–30 | `enum MulticastPreset` | **Completely unused** in `lib/` and `test/` (superseded by `ProtocolPreset`). Remove. |
| `lib/domain/models/multicast_config.dart` | 16 | `IgmpJoinMode.isAsm` | **Completely unused** in `lib/` and `test/`. Remove. |
| `lib/domain/models/multicast_packet.dart` | 49–50 | `MulticastPacket.sendDateTime` | **Completely unused** in `lib/` and `test/`. Remove. |
| `lib/domain/models/multicast_gap_event.dart` | 38–53 | `MulticastGapEvent.toMap()` | **Completely unused** in `lib/` and `test/`. Remove. |
| `lib/ui/features/dashboard/view_models/igmp_tester_view_model.dart` | 160–165 | `IgmpTesterViewModel.ssmFallbackNote` | **Unused in UI and tests.** Either include it in `rawDiagnosticWarning` / `ReceiverPanel` or remove it. |
| `lib/ui/features/dashboard/view_models/igmp_tester_view_model.dart` | 785–789 | `IgmpTesterViewModel.exportGapsCsv(String filePath)` | **Completely unused** in `lib/` and `test/` (UI uses `generateGapsCsvContent()` + `FilePicker.saveFile`). Remove. |
| `lib/data/services/export/csv_export_service.dart` | 126–129 | `CsvExportService.saveCsvToFile` | **Unused in production `lib/`** (only called in `test/gap_detector_test.dart`). Remove or annotate `@visibleForTesting`. |
| `lib/domain/models/igmp_query_event.dart` | 283–301 | `IgmpQueryEvent.toMap()` | **Unused in production `lib/`** (only called in unit tests). Remove or use for JSON export. |
| `lib/ui/features/receiver/views/flooded_streams_sheet.dart` | 86–118 | `FloodedStreamsSheet.showBottomSheetModal` | **Unused in production `lib/`** (desktop app only calls `showDialogModal`; only called in `test/flooding_scanner_test.dart`). |

---

### 3.2. Missing `@visibleForTesting` Annotations on Test-Only Service Hooks
Several methods on production services exist solely for unit tests but are exposed as public APIs without `@visibleForTesting`:
- `lib/data/services/multicast/multicast_receiver_service.dart`:
  - `addStreamForTesting` (line 1259)
  - `processDatagramForTesting` (line 1291)
  - `recalculateStatsForTesting` (line 1305)
- `lib/data/services/multicast/flooding_scanner_service.dart`:
  - `configureFiltersForTesting` (line 488)
  - `markScanCompletedForTesting` (line 510)
  - `processDatagramForTesting` (line 528)
- `lib/data/services/igmp/igmp_query_sniffer.dart`:
  - `parseLineForTesting` (line 323)
  - `parseRawPayloadForTesting` (line 326)
- `lib/data/services/multicast/dscp_socket_helper.dart`:
  - `applySenderDscp` (line 213), `applySenderPreset` (line 228), `readSocketTos` (line 278), `readSocketDscp` (line 304) — only called in `test/dscp_preset_test.dart`.

---

### 3.3. Duplicated UI Widgets & Helpers
- **`_MetricCard` Widget:** Duplicated verbatim between `lib/ui/features/sender/views/sender_panel.dart` (lines 449–519) and `lib/ui/features/receiver/views/receiver_panel.dart` (lines 1310–1380). Extract into `lib/ui/widgets/metric_card.dart`.
- **`_getProtocolPresetIcon` / `_getCategoryIcon`:** Duplicated across `sender_panel.dart` (lines 521–532), `receiver_panel.dart` (lines 1382–1393), and `device_library_dialog.dart` (lines 46–59). Move to a getter or helper on `ProtocolPreset` (or a shared UI helper).
- **`_headerStyle` / `_tableHeaderStyle`:** Duplicated across `sender_panel.dart` (line 443), `receiver_panel.dart` (line 1304), `gap_analysis_table.dart` (line 242), `igmp_query_log_table.dart` (line 262), and `flooded_streams_sheet.dart` (line 963). Centralize in `AppTheme.tableHeaderStyle`.
- **Overlapping Flooding UI in `ReceiverPanel`:** `ReceiverPanel` contains both the legacy single-port `_IgmpSnoopingVerificationCard` ("No-Subscription Server", which only detects `IGMPTEST` packets) and the newer multi-port `FloodedStreamsSheet` ("Scan Unjoined Traffic", which detects `IGMPTEST`, `sACN`, `Art-Net`, `Dante/RTP`, and `Unknown UDP`). Consider consolidating or sharing protocol detection between `MulticastReceiverService._recordUnsubscribedPacket` and `FloodingScannerService.identifyProtocol`.

---

### 3.4. Unused / End-of-Life Dependencies in `pubspec.yaml`
- **File:** `pubspec.yaml`
  1. `cupertino_icons: ^1.0.8` (line 22): **Unused.** No `CupertinoIcons` are referenced anywhere in the project.
  2. `sqlite3_flutter_libs: ^0.6.0+eol` (line 19): **End-of-Life (`+eol`).** The project already uses `sqlite3: ^3.7.1` (resolving to `3.9.1`), which bundles SQLite automatically via Dart Native Assets hooks without needing `sqlite3_flutter_libs`.
  3. `material_ui: any` (line 29): Pin to a concrete version constraint rather than `any` for reproducible builds.

---

## Verification Checklist for Implementing Agents
1. Run `flutter analyze` and confirm zero issues or warnings.
2. Run `flutter test` and verify all existing and newly added unit/widget tests pass.
3. Add regression tests for:
   - Adopting a flooded stream when `groupIp` is `'Unknown Group'` (verifying no crash / `ArgumentError`).
   - `IgmpQuerierWatchdog` resuming ticks after `IgmpTesterViewModel.stopAll()` followed by `startAll()` or `toggleSniffer()`.
   - `MulticastSenderService` packet pacing accuracy for non-100-divisor rates (`44 pps`, `60 pps`, `128 pps`).
   - Fast-Leave measurement on a group with `0` prior packets returning `inconclusive` / `notMeasured` rather than `fastLeaveActive`.
   - Simultaneous SSM `(S, G)` and ASM `(*, G)` streams on the same group address properly calling `leaveMulticast` when the ASM stream stops.
