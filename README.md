# IGMP & Multicast Tester

A cross-platform Flutter desktop application (**Windows, macOS, and Linux**) designed for testing multicast networks and verifying IGMP (Internet Group Management Protocol) behavior across physical switches and routers.

Unlike many existing multicast test tools that require complex command lines, Docker containers, or Linux VMs, **IGMP & Multicast Tester** runs as a standalone desktop executable on Windows, macOS, and Linux with zero external runtime dependencies for standard multicast streaming.

---

## Key Features

- **Multicast Transmitter (Tx)**:
  - Generates UDP multicast streams to any class D multicast address (`224.0.0.0` – `239.255.255.255`).
  - Configurable transmission rates (1 to 1,000+ packets/sec), packet payload sizes (64 to 1,472 bytes MTU), and TTL (Hops).
  - High-precision 50-byte framing header with magic signature (`"IGMPTEST"`), session UUID, 64-bit sequence numbers, and microsecond send timestamps.
  - Multicast Loopback switch for local verification on the same machine.
  - Presets for Organization-Local (`239.255.0.1`), Site-Local (`239.192.0.1`), and Test Groups (`239.1.1.1`).

- **Multicast Receiver & IGMP Join (Rx)**:
  - Joins multicast groups via the host OS kernel stack (`RawDatagramSocket.joinMulticast`), issuing genuine **IGMP Membership Reports** (Join) to upstream IGMP snooping switches.
  - Automatic **IGMP Leave Group** dispatch on stop or application close to maintain clean switch tables.
  - Real-time telemetry: Packets Received vs. Expected, Packet Loss %, Out-of-Order / Duplicate counters, and RFC 3550 Jitter (ms).
  - Live inbound throughput sparkline chart (Mbps).

- **Gap & Packet Loss Analysis**:
  - Automatically identifies missing sequence numbers and logs each drop event with:
    - Gap ID and detection timestamp.
    - Missing sequence range (e.g. `#104 – #128`).
    - Exact number of lost packets.
    - Duration of silence (ms) between the last good packet and the resumed packet.
    - Timestamps of the boundary packets.
  - Real-time filter by sequence number or session ID.
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

### 1. Loopback / Single-Computer Verification
1. Launch the application.
2. Select your active network adapter from the top bar dropdown.
3. Keep **Multicast Loopback** toggled ON in both Tx and Rx tabs.
4. Go to **Receiver (Rx)** and click **JOIN MULTICAST GROUP & START RECEIVING**.
5. Go to **Transmitter (Tx)** and click **START TRANSMITTING MULTICAST STREAM**.
6. Verify 0% packet loss and steady throughput.
7. Stop and restart transmission to verify that sequence gaps are immediately cataloged in the **Gap Analysis** tab.

### 2. Multi-Device Network Validation
1. Run **IGMP & Multicast Tester** on Machine A (Sender) and Machine B / C (Receivers) on the same VLAN / subnet.
2. Machine A transmits multicast traffic to `239.255.0.1:5004`.
3. Machines B and C join the group.
4. Check received packet continuity, gap lengths, and jitter across all receivers to detect switch buffering, Wi-Fi drops, or IGMP snooping timeouts.

---

## License

This project is licensed under the MIT License.
