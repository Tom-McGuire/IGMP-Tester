/// DiffServ (DSCP) QoS priority presets and IPv4 TOS/DSCP codec helpers.
///
/// An IPv4 Type of Service (TOS / Traffic Class) octet packs the 6-bit DSCP
/// code point in its upper 6 bits and the 2-bit Explicit Congestion
/// Notification (ECN) field in its lower 2 bits: `(dscp << 2) | ecn`.
library;

/// Transit verification outcome comparing observed incoming DSCP against the
/// expected DSCP tag for a multicast stream.
enum DscpTransitStatus {
  /// No incoming TOS/DSCP observation is available or no expectation applies.
  unverified,

  /// Observed DSCP matches the expected DSCP value.
  preserved,

  /// Expected non-zero DSCP was remarked to a different non-zero DSCP value.
  remarkedOrStripped,

  /// Expected non-zero DSCP was stripped down to Best Effort (`0`).
  remarkedToZero;

  /// Whether this status indicates that QoS markings were altered in transit.
  bool get isAlert =>
      this == DscpTransitStatus.remarkedOrStripped ||
      this == DscpTransitStatus.remarkedToZero;

  /// Whether the observed DSCP matched the expected DSCP.
  bool get isPreserved => this == DscpTransitStatus.preserved;

  /// Whether DSCP transit verification could not be determined.
  bool get isUnverified => this == DscpTransitStatus.unverified;
}

/// Standard DiffServ (DSCP) QoS priority presets for broadcast and AV multicast.
enum DscpPreset {
  /// Standard unprioritized traffic (`DSCP 0`, `TOS 0x00`).
  bestEffort(0, 'BE', 'Best Effort / Default'),

  /// Call signaling and broadcast control traffic (`DSCP 24`, `TOS 0x60`).
  cs3(24, 'CS3', 'Call Signaling / Broadcast'),

  /// Real-time video / NDI traffic (`DSCP 34`, `TOS 0x88`).
  af41(34, 'AF41', 'Video / NDI'),

  /// Expedited real-time audio / AES67 / Dante traffic (`DSCP 46`, `TOS 0xB8`).
  ef(46, 'EF', 'Audio / AES67 / Dante'),

  /// PTPv2 clock sync and network control traffic (`DSCP 56`, `TOS 0xE0`).
  cs7(56, 'CS7', 'PTPv2 / Network Control');

  /// Minimum valid 6-bit DSCP code point (`0`).
  static const int minDscp = 0;

  /// Maximum valid 6-bit DSCP code point (`63`).
  static const int maxDscp = 63;

  /// Bitmask isolating the 6-bit DSCP value (`0x3F`).
  static const int dscpMask = 0x3F;

  /// Bitmask isolating the 2-bit ECN field (`0x03`).
  static const int ecnMask = 0x03;

  /// The 6-bit DiffServ code point (`0..63`).
  final int dscpValue;

  /// The short IETF DiffServ class name (for example, `EF` or `AF41`).
  final String shortName;

  /// The typical AV or network traffic class served by this preset.
  final String trafficClassDescription;

  const DscpPreset(
    this.dscpValue,
    this.shortName,
    this.trafficClassDescription,
  );

  /// The 8-bit IPv4 TOS / Traffic Class byte with zeroed ECN bits (`dscpValue << 2`).
  int get tosByte => encodeTosByte(dscpValue);

  /// Compact badge label such as `EF (46)` or `BE (0)`.
  String get shortLabel => '$shortName ($dscpValue)';

  /// Full human-readable label such as `EF (46) — Audio / AES67 / Dante`.
  String get label => '$shortLabel — $trafficClassDescription';

  /// Display string intended for dropdown selectors.
  String get dropdownLabel => label;

  /// Hexadecimal representation of [tosByte] (for example, `0xB8`).
  String get tosHex =>
      '0x${tosByte.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  /// Whether [dscp] is within the valid 6-bit DiffServ range (`0..63`).
  static bool isValidDscp(int dscp) => dscp >= minDscp && dscp <= maxDscp;

  /// Encodes a 6-bit [dscp] value and optional 2-bit [ecn] flags into an 8-bit
  /// IPv4 TOS byte.
  ///
  /// Both [dscp] and [ecn] are masked to their valid bit widths (`0x3F` and
  /// `0x03` respectively).
  static int encodeTosByte(int dscp, {int ecn = 0}) =>
      ((dscp & dscpMask) << 2) | (ecn & ecnMask);

  /// Extracts the 6-bit DSCP value (`0..63`) from an 8-bit IPv4 [tosByte],
  /// discarding the lower 2 ECN bits.
  static int extractDscpFromTos(int tosByte) => (tosByte >> 2) & dscpMask;

  /// Extracts the 2-bit ECN field (`0..3`) from an 8-bit IPv4 [tosByte].
  static int extractEcnFromTos(int tosByte) => tosByte & ecnMask;

  /// Returns the [DscpPreset] matching [dscp], or `null` if [dscp] is not one
  /// of the predefined presets.
  static DscpPreset? tryFromDscpValue(int dscp) {
    for (final preset in values) {
      if (preset.dscpValue == dscp) return preset;
    }
    return null;
  }

  /// Returns the [DscpPreset] matching [dscp], or [fallback] when unmatched.
  static DscpPreset fromDscpValue(
    int dscp, {
    DscpPreset fallback = DscpPreset.bestEffort,
  }) => tryFromDscpValue(dscp) ?? fallback;

  /// Extracts the DSCP code point from [tosByte] (ignoring ECN bits) and
  /// returns the matching [DscpPreset], or `null` if unmatched.
  static DscpPreset? tryFromTosByte(int tosByte) =>
      tryFromDscpValue(extractDscpFromTos(tosByte));

  /// Extracts the DSCP code point from [tosByte] (ignoring ECN bits) and
  /// returns the matching [DscpPreset], or [fallback] when unmatched.
  static DscpPreset fromTosByte(
    int tosByte, {
    DscpPreset fallback = DscpPreset.bestEffort,
  }) => tryFromTosByte(tosByte) ?? fallback;

  /// Formats a compact badge string for [dscp].
  ///
  /// Returns `'EF (46)'` for known presets or `'DSCP <value>'` for arbitrary
  /// 6-bit code points such as `18`.
  static String formatDscpBadge(int dscp) {
    final normalized = dscp & dscpMask;
    final preset = tryFromDscpValue(normalized);
    if (preset != null) {
      return preset.shortLabel;
    }
    return 'DSCP $normalized';
  }

  /// Evaluates whether an [observedDscp] preserved or altered an [expectedDscp]
  /// tag across the network.
  ///
  /// Returns [DscpTransitStatus.unverified] if either value is `null` or out of
  /// range (`0..63`), or if [expectedDscp] is `0` while [observedDscp] is
  /// non-zero. Returns [DscpTransitStatus.remarkedToZero] when a non-zero
  /// [expectedDscp] arrives stripped to `0`, and
  /// [DscpTransitStatus.remarkedOrStripped] when a non-zero [expectedDscp]
  /// arrives remarked to a different non-zero value.
  static DscpTransitStatus evaluateTransitStatus({
    required int? expectedDscp,
    required int? observedDscp,
  }) {
    if (expectedDscp == null || observedDscp == null) {
      return DscpTransitStatus.unverified;
    }
    if (!isValidDscp(expectedDscp) || !isValidDscp(observedDscp)) {
      return DscpTransitStatus.unverified;
    }
    if (observedDscp == expectedDscp) {
      return DscpTransitStatus.preserved;
    }
    if (expectedDscp == 0) {
      return DscpTransitStatus.unverified;
    }
    if (observedDscp == 0) {
      return DscpTransitStatus.remarkedToZero;
    }
    return DscpTransitStatus.remarkedOrStripped;
  }
}
