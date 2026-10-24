# Security & Architecture Code Review — IGMP & Multicast Tester

This document contains a prioritized list of security findings, functional bugs, platform configuration issues, and performance optimizations identified during a full codebase audit of `igmp_tester`. It is structured as an actionable specification for an engineering agent to implement and verify.

---

## Priority 1: High-Impact Functional & Reliability Bugs

### 1.1. Multi-Stream Demultiplexing Bug on Shared UDP Ports (`MulticastReceiverService`)
- **Files:**
  - `lib/domain/models/multicast_packet.dart`
  - `lib/data/services/multicast/multicast_sender_service.dart`
  - `lib/data/services/multicast/multicast_receiver_service.dart` (lines 146–168)
- **Root Cause:**
  - By default, Batch Join creates multiple multicast stream subscriptions on the same UDP port (`5004`), sharing a single `RawDatagramSocket` bound to `0.0.0.0:5004`.
  - `dart:io`'s `Datagram` exposes the *sender's source IP* (`datagram.address`), not the *destination multicast group IP*.
  - In `_processDatagram`, when a packet arrives with a `sessionId` not yet in `_sessionToStreamId`, the service iterates `_streams.values` and binds the session to the first stream on that port where `activeSessionId == null`.
  - **Failure Modes:**
    1. **Wrong Stream Attribution:** If `Stream 5 (239.255.0.5)` transmits before `Stream 1 (239.255.0.1)`, `Stream 5`'s packets are permanently attributed to `Group 1`.
    2. **Sender Restart Collisions:** If the transmitter is stopped and restarted (generating new `sessionId`s) while receivers remain running, all receiver contexts on port `5004` already have `activeSessionId != null`. The loop finds no candidate, and line 167 (`ctx ??= _streams.values.firstWhere(...)`) dumps all restarted streams' packets into the first stream on that port, corrupting sequence tracking and generating thousands of false-positive gaps.
    3. **Cross-Port Fallback:** The `orElse: () => _streams.values.first` fallback on line 167 can attribute a packet to a stream listening on a different port if no matching stream is found.
- **Required Fix:**
  - Encode the target multicast `groupAddress` (e.g., 4 bytes IPv4 octets) into the `MulticastPacket` header (or deterministically embed the 8-hex-char IPv4 address into the 16-byte `sessionId`, e.g., `<8-hex-group-ip><8-hex-timestamp>`), so `_processDatagram` can deterministically match incoming packets to the `_ReceiverStreamContext` whose `(groupAddress, port)` matches the packet's destination group and port.
  - If no subscribed `_ReceiverStreamContext` matches `(groupAddress, port)`, drop/ignore the packet instead of falling back to `_streams.values.first`.
  - Clean up `_sessionToStreamId` entries belonging to a stream when `stopStream(streamId)` is called.

### 1.2. OS `IP_ADD_MEMBERSHIP` Per-Socket Limit & Swallowed Exceptions (`MulticastReceiverService`)
- **File:** `lib/data/services/multicast/multicast_receiver_service.dart` (lines 78–107)
- **Root Cause:**
  1. `startStream` shares a single `RawDatagramSocket` per UDP port and calls `socket.joinMulticast(targetGroup, rawInterface)`. On Windows, macOS, and Linux (depending on kernel defaults), `IP_MAX_MEMBERSHIPS` often defaults to **20 multicast groups per socket**. Joining >20 groups on port `5004` on a single socket throws a `SocketException`.
  2. Lines 101–107 wrap `socket.joinMulticast` in nested `try / catch (_) {}` blocks that completely swallow any exception. If `joinMulticast` fails, the stream still appears active in the UI even though no IGMP membership report was sent.
- **Required Fix:**
  - Do not silently swallow the inner `joinMulticast` exception—rethrow a descriptive error so `IgmpTesterViewModel` can display it in `GlobalErrorBanner`.
  - Consider binding one `RawDatagramSocket` per `_ReceiverStreamContext` (using `reuseAddress: true` and `reusePort: !Platform.isWindows`) or pooling sockets in batches of ≤16 memberships per socket so 50–100 group saturation tests do not hit the kernel `IP_MAX_MEMBERSHIPS` limit.

---

## Priority 2: Security & Input Hardening

### 2.1. Unbounded Memory Growth / DoS in Gap Tracking (`MulticastReceiverService`)
- **File:** `lib/data/services/multicast/multicast_receiver_service.dart` (lines 24, 38–39, 222–223, 339–343)
- **Root Cause:**
  - `_allGaps` and `ctx.gaps` grow without bound. High packet loss or spoofed packets with incrementing sequence numbers will allocate `MulticastGapEvent` objects indefinitely until OOM.
  - `_recalculateStats()` (called every 500ms) iterates over every element in `ctx.gaps` (`for (final g in ctx.gaps)`) to compute `sMaxGapPkts`, `sMaxGapMs`, and `sTotalGapMs`, causing `O(N)` CPU overhead on the UI isolate.
- **Required Fix:**
  - Cap `_allGaps` and `ctx.gaps` (e.g., max `5000` entries, evicting oldest or keeping a sliding window, matching the pattern in `IgmpQuerySnifferService._events`).
  - Track `totalGapsCount`, `maxGapPackets`, `maxGapDurationMs`, and `sumGapDurationMs` as incremental fields on `_ReceiverStreamContext` updated in `_processDatagram` when a gap occurs, eliminating the `for (final g in ctx.gaps)` loop inside `_recalculateStats()`.

### 2.2. CSV Formula Injection & Unescaped Strings (`CsvExportService`)
- **File:** `lib/data/services/export/csv_export_service.dart` (lines 6–38)
- **Root Cause:**
  - `generateGapsCsv` manually interpolates values into a `StringBuffer` (`'${gap.id},"${gap.streamName}",${gap.groupAddress},${gap.port},${gap.sessionId},...'`) instead of using the `csv` package already listed in `pubspec.yaml`.
  - `gap.sessionId` comes from raw network packets (`MulticastPacket.decode`) and `gap.streamName` comes from user input. Unescaped quotes, commas, newlines, or leading formula triggers (`=`, `+`, `-`, `@`, `\t`, `\r`) can corrupt the CSV structure or trigger spreadsheet formula execution when opened in Excel/LibreOffice.
- **Required Fix:**
  - Sanitize `rawSession` in `MulticastPacket.decode` (`lib/domain/models/multicast_packet.dart`, line 85) so only printable ASCII alphanumeric/hex/hyphen characters are accepted.
  - Sanitize or quote string cells in `CsvExportService.generateGapsCsv` (prefixing cells starting with `=`, `+`, `-`, `@` with a single quote `'` or using `package:csv` to escape quotes/delimiters).

### 2.3. Multicast IPv4 Address, Port, TTL, Rate, and Size Input Validation
- **Files:**
  - `lib/domain/models/multicast_config.dart` (lines 61–67)
  - `lib/ui/features/sender/views/sender_panel.dart` (lines 9–237)
  - `lib/ui/features/receiver/views/receiver_panel.dart` (lines 10–170)
- **Root Cause:**
  - `SenderPanel` and `ReceiverPanel` accept arbitrary strings for `groupAddress` and arbitrary integers for `port`, `ttl`, `packetsPerSecond`, and `packetSizeBytes`.
  - Entering a unicast IP in `SenderPanel` causes the app to flood a unicast target with UDP traffic; entering an invalid IP throws an unhandled `FormatException` in `InternetAddress(streamConfig.groupAddress)`.
  - `MulticastStreamConfig.incrementIp` does not validate octets (`0..255`) and can overflow past `239.255.255.255` into reserved Class E space (`240.0.0.0+`). Batch port incrementing (`basePort + i`) can also overflow `65535`.
- **Required Fix:**
  - Add static validation utilities on `MulticastStreamConfig`:
    - `isValidMulticastIpv4(String ip)`: verifies 4 octets, each `0..255`, with first octet in `224..239`.
    - Clamp/validate `port` (`1..65535`), `ttl` (`1..255`), `packetsPerSecond` (`1..5000`), and `packetSizeBytes` (`50..1472`).
    - Clamp `incrementIp` so it stays within `224.0.0.0`–`239.255.255.255`, and clamp incremented ports to `<= 65535`.
  - Show validation errors in the Add/Batch dialogs in `SenderPanel` and `ReceiverPanel` before adding streams.

### 2.4. Windows Working-Directory Binary Hijacking in `findTSharkPath` (`IgmpQuerySnifferService`)
- **File:** `lib/data/services/igmp/igmp_query_sniffer.dart` (lines 43–49)
- **Root Cause:**
  - On Windows, `Process.run('where', ['tshark'])` searches the current working directory before `PATH` unless invoked carefully.
- **Required Fix:**
  - Verify that any candidate path returned by `where` is an absolute path outside the current working directory (or pass `['$PATH:tshark']` to `where.exe`, which forces `where.exe` to search only the `PATH` environment variable and ignore the current directory).

---

## Priority 3: Platform Configuration & Secondary Bugs

### 3.1. macOS Entitlements Block Networking in Release Builds
- **Files:**
  - `macos/Runner/Release.entitlements`
  - `macos/Runner/DebugProfile.entitlements`
- **Root Cause:**
  - `Release.entitlements` enables `com.apple.security.app-sandbox` without `com.apple.security.network.client` or `com.apple.security.network.server`. `DebugProfile.entitlements` is missing `com.apple.security.network.client`.
  - Additionally, macOS App Sandbox prevents executing external binaries like `/opt/homebrew/bin/tshark`.
- **Required Fix:**
  - Add `<key>com.apple.security.network.client</key><true/>` and `<key>com.apple.security.network.server</key><true/>` to both `Release.entitlements` and `DebugProfile.entitlements` (or disable `com.apple.security.app-sandbox` if distributing outside the Mac App Store so `tshark` execution is permitted).

### 3.2. Aggregate `avgGapDurationMs` Missing in `MulticastReceiverService`
- **File:** `lib/data/services/multicast/multicast_receiver_service.dart` (lines 392–406)
- **Root Cause:**
  - `_recalculateStats` computes `sAvgGapMs` per stream, but never computes or passes `avgGapDurationMs` when constructing `_aggregateStats`. As a result, `_aggregateStats.avgGapDurationMs` is always `0.0` (including in the exported CSV summary header).
- **Required Fix:**
  - Compute the weighted average gap duration across all gaps in `_recalculateStats` and pass `avgGapDurationMs` to `_aggregateStats`.

### 3.3. TShark `stderr` Stream Not Drained (`IgmpQuerySnifferService`)
- **File:** `lib/data/services/igmp/igmp_query_sniffer.dart` (lines 102–115)
- **Root Cause:**
  - `_process?.stderr` is never drained or listened to. If `tshark` writes to `stderr`, the pipe buffer can fill and stall the child process, and startup failures (such as permission denied or invalid interface name) are silently ignored.
- **Required Fix:**
  - Drain or listen to `_process?.stderr` (e.g., `_process?.stderr.drain()` or capture the last error line to surface to the user if `_process` exits with a non-zero exit code).

---

## Priority 4: Performance & Code Hygiene

### 4.1. Pre-Allocate Packet Buffers in `MulticastSenderService`
- **Files:**
  - `lib/domain/models/multicast_packet.dart`
  - `lib/data/services/multicast/multicast_sender_service.dart` (lines 109–131)
- **Issue:**
  - `MulticastPacket.encode()` allocates a new `Uint8List`, encodes ASCII headers, and loops over every payload byte (`50..totalSize`) on **every single packet**. At 20–100 streams × 100–1,000 PPS, this creates tens of megabytes per second of short-lived heap allocations.
- **Required Fix:**
  - Pre-encode a template `Uint8List` buffer once per `_ActiveSenderContext` when starting the stream, and in the `Timer.periodic` loop only update the 8-byte `sequenceNumber` (offset 26) and 8-byte `sendTimestampUs` (offset 34) in-place using a `ByteData` view before calling `socket.send()`.

### 4.2. Dispose `TextEditingController` Instances in Dialogs
- **Files:**
  - `lib/ui/features/sender/views/sender_panel.dart`
  - `lib/ui/features/receiver/views/receiver_panel.dart`
- **Issue:**
  - `_showAddStreamDialog`, `_showBatchDialog`, `_showAddGroupDialog`, and `_showBatchGroupDialog` create `TextEditingController`s inside stateless methods and never dispose them.
- **Required Fix:**
  - Extract these dialogs into dedicated `StatefulWidget`s (or dispose the controllers when `showDialog` completes) so controllers are properly disposed.

### 4.3. Remove Unused Dependencies & Dead Code
- **Files:**
  - `pubspec.yaml`: Remove unused `path_provider` and `path` dependencies (and either use `csv` in `CsvExportService` or remove it).
  - `lib/data/services/export/csv_export_service.dart` & `lib/ui/features/dashboard/view_models/igmp_tester_view_model.dart`: Remove unused `saveCsvToFile` / `exportGapsCsv` if `FilePicker.saveFile(bytes: ...)` is the standard export mechanism, or wire them into unit tests.

---

## Verification Checklist for Implementing Agent
1. Run `flutter analyze` and ensure zero warnings or lint errors.
2. Run `flutter test` and add unit tests covering:
   - Multi-stream packet demultiplexing on a shared UDP port (including sender restarts with new session IDs).
   - Multicast IPv4 and port validation (`isValidMulticastIpv4`, `incrementIp` clamping).
   - CSV export escaping/sanitization against formula injection and embedded quotes.
   - Gap ring-buffer capping and aggregate `avgGapDurationMs` calculation.
