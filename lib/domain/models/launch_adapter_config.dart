import 'network_interface_info.dart';

/// Configuration for pre-selecting a network adapter from launch CLI arguments.
class LaunchAdapterConfig {
  /// The optional IPv4 address passed via `--adapter-ip`.
  final String? adapterIp;

  /// The optional interface name passed via `--adapter-name`.
  final String? adapterName;

  /// Creates a launch adapter configuration with optional overrides.
  const LaunchAdapterConfig({this.adapterIp, this.adapterName});

  /// Parses `--adapter-ip` and `--adapter-name` overrides from CLI [args].
  ///
  /// Supports both space-separated (`--flag value`) and equals-separated
  /// (`--flag=value`) forms. Values are trimmed and empty or whitespace-only
  /// values are normalized to `null`. Unknown flags and trailing flags without
  /// a following value are ignored.
  factory LaunchAdapterConfig.fromArgs(List<String> args) {
    String? ip;
    String? name;
    for (var i = 0; i < args.length; i++) {
      final ipMatch = _readFlagValue(args, i, '--adapter-ip');
      if (ipMatch != null) {
        ip = ipMatch.value;
        i = ipMatch.nextIndex;
        continue;
      }
      final nameMatch = _readFlagValue(args, i, '--adapter-name');
      if (nameMatch != null) {
        name = nameMatch.value;
        i = nameMatch.nextIndex;
      }
    }
    return LaunchAdapterConfig(adapterIp: ip, adapterName: name);
  }

  /// Whether either [adapterIp] or [adapterName] contains a non-empty override.
  bool get hasAdapterOverride =>
      (adapterIp != null && adapterIp!.trim().isNotEmpty) ||
      (adapterName != null && adapterName!.trim().isNotEmpty);

  /// Whether any CLI adapter override is configured.
  ///
  /// Alias for [hasAdapterOverride].
  bool get hasOverride => hasAdapterOverride;

  /// Selects the initial interface from [interfaces] using CLI overrides.
  ///
  /// Returns `null` when [interfaces] is empty. Otherwise resolves in priority
  /// order:
  /// 1. Exact IPv4 match against trimmed [adapterIp].
  /// 2. Case-insensitive exact match, then substring match against
  ///    [adapterName].
  /// 3. First non-loopback/non-unspecified interface (`127.0.0.1` and `0.0.0.0`
  ///    excluded), falling back to `interfaces.first`.
  NetworkInterfaceInfo? selectInitialInterface(
    List<NetworkInterfaceInfo> interfaces,
  ) {
    if (interfaces.isEmpty) return null;

    final targetIp = adapterIp?.trim();
    if (targetIp != null && targetIp.isNotEmpty) {
      for (final iface in interfaces) {
        if (iface.ip.trim() == targetIp) {
          return iface;
        }
      }
    }

    final targetName = adapterName?.trim();
    if (targetName != null && targetName.isNotEmpty) {
      final needle = targetName.toLowerCase();
      for (final iface in interfaces) {
        if (iface.name.toLowerCase() == needle) {
          return iface;
        }
      }
      for (final iface in interfaces) {
        if (iface.name.toLowerCase().contains(needle)) {
          return iface;
        }
      }
    }

    return interfaces.firstWhere(
      (i) => i.ip != '127.0.0.1' && i.ip != '0.0.0.0',
      orElse: () => interfaces.first,
    );
  }

  static ({String? value, int nextIndex})? _readFlagValue(
    List<String> args,
    int index,
    String flag,
  ) {
    final arg = args[index];
    if (arg == flag) {
      if (index + 1 < args.length) {
        return (value: _normalize(args[index + 1]), nextIndex: index + 1);
      }
      return null;
    }
    final prefix = '$flag=';
    if (arg.startsWith(prefix)) {
      return (
        value: _normalize(arg.substring(prefix.length)),
        nextIndex: index,
      );
    }
    return null;
  }

  static String? _normalize(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchAdapterConfig &&
          runtimeType == other.runtimeType &&
          adapterIp == other.adapterIp &&
          adapterName == other.adapterName;

  @override
  int get hashCode => Object.hash(adapterIp, adapterName);

  @override
  String toString() =>
      'LaunchAdapterConfig(adapterIp: $adapterIp, adapterName: $adapterName)';
}
