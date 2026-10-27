# IGMP & Multicast Tester

A cross-platform Flutter desktop application (**Windows, macOS, and Linux**) designed for testing multicast networks, verifying IGMP (Internet Group Management Protocol) behavior, and performing multi-stream network saturation testing across physical switches and routers.

Unlike many existing multicast test tools that require complex command lines, Docker containers, or Linux VMs, **IGMP & Multicast Tester** runs as a standalone desktop executable on Windows, macOS, and Linux with zero external runtime dependencies for standard multicast streaming.

---

## Key Features

- **Multi-Stream Multicast Transmitter (Tx) & Saturation Engine**:
  - Transmit multiple concurrent UDP multicast streams across different class D multicast groups (`224.0.0.0` – `239.255.255.255`).
  - **Batch Stream Generator**: Instantly generate $N$ streams (e.g. 10, 20, 50, or 100 streams from `239.255.0.1` to `239.255.0.20` at 100 pps each $\rightarrow$ 2,000 pps aggregate).
  - Configurable rates (1 to 2,000+ packets/sec per stream), packet payload sizes (64 to 1,472 bytes MTU), and TTL (Hops).
  - High-precision 50-byte framing header with magic signature (`"IGMPTEST"`), stream/session UUID, 64-bit sequence numbers, and microsecond send timestamps.
  - Per-stream controls (start, pause, edit, delete) plus global "Start All / Stop All".
  - Aggregate outbound telemetry: Combined PPS, Total Bandwidth (Mbps), and Data Volume (MB/GB).

- **Multi-Group Multicast Receiver & IGMP Join (Rx)**:
  - Subscribes to multiple multicast groups simultaneously across single or distinct UDP ports.
  - Issues genuine **IGMP Membership Reports** (Join) through the host OS kernel stack (`RawDatagramSocket.joinMulticast`) for every configured group to test switch IGMP snooping table capacity.
  - **Batch Group Join**: 1-click subscription to ranges of multicast addresses.
  - Automatic **IGMP Leave Group** dispatch on stop or application close to maintain clean switch tables.
  - Per-stream and aggregate telemetry: Packets Received vs. Expected, Packet Loss %, Out-of-Order / Duplicate counters, and RFC 3550 Jitter (ms).
  - Live aggregate inbound throughput sparkline chart (Mbps).

- **Stream-Aware Gap & Packet Loss Analysis**:
  - Automatically identifies missing sequence numbers and logs each drop event with:
    - Target Stream and Group Address (e.g. `Stream 3 (239.255.0.3:5004)`).
    - Missing sequence range (e.g. `#104 – #128`).
    - Exact number of lost packets.
    - Duration of silence (ms) between the last good packet and the resumed packet.
    - Timestamps of the boundary packets.
  - **Isolate Network Issues**: Compare whether drop events occurred across all streams at once (link flap or port buffer exhaustion) or only on specific groups (IGMP snooping table overflow or multicast hash collisions).
  - Real-time search/filter by stream name, multicast group, sequence number, or session ID.
  - **Export to CSV**: Generates RFC-compliant CSV reports with session summary metrics and tabular gap records.

- **IGMP Query Monitor & Querier Watchdog**:
  - Integrates with the local `tshark` / `dumpcap` engine (if installed) to sniff raw IGMP (`ip.proto == 2`) packets:
    - IGMPv1, v2, and v3 General Queries (`224.0.0.1`).
    - Group-Specific Queries.
    - Membership Reports & Leaves.
    - Querier IP addresses and Max Response Time windows.
  - **Querier Cadence Watchdog**:
    - Tracks seconds since the last query was observed on the network.
    - Displays Active (<125s), Warning (125s–260s), and Critical (>260s) indicators to alert users if the querier has gone silent and switch pruning is imminent.

- **Familiar Dark Theme UI**:
  - Matches the VS Code dark theme and UI design language of network tooling companion apps (`net-services`, `packet-inspector`, `syslog-server`, and `tshark-interface`).
  - Compact density, responsive layout, and desktop shortcuts.

---

## ⚠️ Note on Windows / macOS Security Prompts

These tools are free and independent projects and are not yet code-signed with expensive commercial certificates:

- **Windows**: If SmartScreen appears, click **"More info"** → **"Run anyway"**.
- **macOS**: Right-click the `.app` file, select **Open**, and confirm the prompt (or run `xattr -c <AppName>.app` in Terminal).

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.13+ or higher)
- C++ Desktop Build Tools (Visual Studio on Windows, Xcode on macOS, build-essential on Linux)
- *(Optional)* [Wireshark / TShark](https://www.wireshark.org) with Npcap / libpcap (required only for raw IGMP Query capture; standard multicast streaming and gap analysis require no extra software).

### Installation & Run

1. Clone the repository:
   ```bash
   git clone https://github.com/Tom-McGuire/IGMP-Tester.git
   cd IGMP-Tester
   ```

2. Fetch dependencies:
   ```bash
   flutter pub get
   ```

3. Run on your desktop platform:
   ```bash
   # Windows
   flutter run -d windows

   # macOS
   flutter run -d macos

   # Linux
   flutter run -d linux
   ```

4. Build standalone Release executable:
   ```bash
   flutter build windows
   # Output: build/windows/x64/runner/Release/igmp_tester.exe
   ```

---

## Testing Scenarios

### 1. Multi-Stream Network Saturation Testing
1. On the **Transmitter (Tx)** tab, click **Batch Generator**.
2. Set stream count to `20`, starting IP to `239.255.0.1`, rate to `100 pps`, and packet size to `1400 bytes`.
3. Click **Generate Streams**.
4. Click **START TRANSMITTING ALL STREAMS (20)**.
5. You are now streaming 2,000 packets/sec (~22.4 Mbps aggregate multicast) across 20 distinct multicast groups.
6. On the **Receiver (Rx)** machine, click **Batch Join** and subscribe to the same 20 groups.
7. Click **JOIN ALL MULTICAST GROUPS (20) & START RECEIVING**.
8. Inspect individual stream loss rates in the table and overall continuity in the **Gap Analysis** tab.

### 2. Single-Machine Loopback Test
1. Select your active network adapter from the top bar dropdown.
2. Keep **Multicast Loopback** toggled ON in both Tx and Rx tabs.
3. On the **Receiver (Rx)** tab, click **JOIN ALL MULTICAST GROUPS & START RECEIVING**.
4. On the **Transmitter (Tx)** tab, click **START TRANSMITTING ALL STREAMS**.
5. Verify 0% packet loss and steady aggregate throughput.

---

## License

This project is licensed under the MIT License.
