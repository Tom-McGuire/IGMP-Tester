/// Cross-platform IPv4 TOS/DSCP raw socket option helpers for UDP multicast.
///
/// Wraps `setsockopt`/`getsockopt` calls via [RawSocketOption] so unsupported
/// operating systems, Windows QoS restrictions, or sandboxed environments
/// degrade gracefully without throwing.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../domain/models/dscp_preset.dart';

/// Platform-specific `IPPROTO_IP`, `IP_TOS`, and `IP_RECVTOS` socket option IDs.
class DscpPlatformSocketOptions {
  /// Protocol level (`IPPROTO_IP`).
  final int level;

  /// Socket option ID for outgoing IPv4 TOS (`IP_TOS`).
  final int ipTosOption;

  /// Socket option ID for enabling incoming TOS metadata (`IP_RECVTOS`).
  final int ipRecvTosOption;

  const DscpPlatformSocketOptions({
    required this.level,
    required this.ipTosOption,
    required this.ipRecvTosOption,
  });
}

/// Outcome of applying a DiffServ/TOS socket option to a [RawDatagramSocket].
class DscpSocketApplyResult {
  /// Whether the socket option was applied without throwing.
  final bool success;

  /// The IPv4 TOS byte written to the socket (`IP_TOS`), or `null` when
  /// skipped, failed, or inapplicable (such as `IP_RECVTOS`).
  final int? appliedTosByte;

  /// Diagnostic warning describing why applying the option was skipped or
  /// failed, if any.
  final String? warningMessage;

  const DscpSocketApplyResult({
    required this.success,
    this.appliedTosByte,
    this.warningMessage,
  });

  /// The 6-bit DSCP value derived from [appliedTosByte], or `null` if none was
  /// applied.
  int? get appliedDscp => appliedTosByte == null
      ? null
      : DscpPreset.extractDscpFromTos(appliedTosByte!);
}

/// OS-safe helper for configuring `IP_TOS` and `IP_RECVTOS` on
/// [RawDatagramSocket] instances across Linux, macOS, and Windows.
///
/// Note that Dart's [RawDatagramSocket.receive] returns a [Datagram] without
/// ancillary `recvmsg` control message headers (`cmsg`), so
/// [enableReceiveTos] safely primes the OS socket without assuming Dart exposes
/// per-datagram TOS metadata on all platforms.
class DscpSocketHelper {
  DscpSocketHelper._();

  /// Socket level constant `IPPROTO_IP` across Linux, macOS, and Windows.
  static const int ipProtoIp = 0;

  static const DscpPlatformSocketOptions _linuxOptions =
      DscpPlatformSocketOptions(
        level: ipProtoIp,
        ipTosOption: 1,
        ipRecvTosOption: 13,
      );

  static const DscpPlatformSocketOptions _darwinOptions =
      DscpPlatformSocketOptions(
        level: ipProtoIp,
        ipTosOption: 3,
        ipRecvTosOption: 27,
      );

  static const DscpPlatformSocketOptions _windowsOptions =
      DscpPlatformSocketOptions(
        level: ipProtoIp,
        ipTosOption: 3,
        ipRecvTosOption: 40,
      );

  /// Resolves the `IPPROTO_IP` socket option constants for [operatingSystem]
  /// (matching [Platform.operatingSystem] values), or returns `null` if the
  /// operating system is unsupported.
  static DscpPlatformSocketOptions? platformOptionsForOS(
    String operatingSystem,
  ) {
    switch (operatingSystem.toLowerCase()) {
      case 'linux':
      case 'android':
        return _linuxOptions;
      case 'macos':
      case 'ios':
        return _darwinOptions;
      case 'windows':
        return _windowsOptions;
      default:
        return null;
    }
  }

  /// Resolves the `IPPROTO_IP` socket option constants for the host OS.
  static DscpPlatformSocketOptions? get currentPlatformOptions {
    if (Platform.isLinux || Platform.isAndroid) return _linuxOptions;
    if (Platform.isMacOS || Platform.isIOS) return _darwinOptions;
    if (Platform.isWindows) return _windowsOptions;
    return null;
  }

  /// Builds a [RawSocketOption] for `IP_TOS` from [dscp] (`0..63`) and
  /// optional [ecn] (`0..3`), or returns `null` if parameters or platform are
  /// unsupported.
  static RawSocketOption? buildSenderTosOption(
    int dscp, {
    int ecn = 0,
    String? operatingSystem,
  }) {
    if (!DscpPreset.isValidDscp(dscp) || ecn < 0 || ecn > 3) {
      return null;
    }
    final options = operatingSystem != null
        ? platformOptionsForOS(operatingSystem)
        : currentPlatformOptions;
    if (options == null) return null;

    final tosByte = DscpPreset.encodeTosByte(dscp, ecn: ecn);
    return RawSocketOption.fromInt(options.level, options.ipTosOption, tosByte);
  }

  /// Builds a [RawSocketOption] for `IP_RECVTOS`, or returns `null` if the
  /// platform is unsupported.
  static RawSocketOption? buildReceiveTosOption({
    bool enabled = true,
    String? operatingSystem,
  }) {
    final options = operatingSystem != null
        ? platformOptionsForOS(operatingSystem)
        : currentPlatformOptions;
    if (options == null) return null;

    return RawSocketOption.fromBool(
      options.level,
      options.ipRecvTosOption,
      enabled,
    );
  }

  /// Applies IPv4 `IP_TOS` for [dscp] (`0..63`) and optional [ecn] (`0..3`) on
  /// [socket], returning a detailed [DscpSocketApplyResult].
  ///
  /// Never throws, even when [socket] is `null`, closed, IPv6-only, or denied
  /// by the kernel/sandbox.
  static DscpSocketApplyResult applySenderDscpWithResult(
    RawDatagramSocket? socket,
    int dscp, {
    int ecn = 0,
  }) {
    if (!DscpPreset.isValidDscp(dscp)) {
      return DscpSocketApplyResult(
        success: false,
        warningMessage: 'Invalid DSCP value $dscp (expected 0..63).',
      );
    }
    if (ecn < 0 || ecn > 3) {
      return DscpSocketApplyResult(
        success: false,
        warningMessage: 'Invalid ECN value $ecn (expected 0..3).',
      );
    }

    final tosByte = DscpPreset.encodeTosByte(dscp, ecn: ecn);

    if (socket == null) {
      return DscpSocketApplyResult(
        success: false,
        warningMessage: 'Socket is null; IP_TOS ($tosByte) was not applied.',
      );
    }

    final option = buildSenderTosOption(dscp, ecn: ecn);
    if (option == null) {
      return DscpSocketApplyResult(
        success: false,
        warningMessage:
            'IP_TOS is unsupported on platform "${Platform.operatingSystem}".',
      );
    }

    try {
      socket.setRawOption(option);
      return DscpSocketApplyResult(success: true, appliedTosByte: tosByte);
    } catch (e) {
      return DscpSocketApplyResult(
        success: false,
        warningMessage: 'Failed to set IP_TOS ($tosByte): $e',
      );
    }
  }

  /// Applies IPv4 `IP_TOS` for [dscp] (`0..63`) on [socket].
  ///
  /// Returns `true` if the option succeeded, or `false` if [socket] is `null`,
  /// [dscp] is out of range, or the OS rejected `setRawOption`.
  @visibleForTesting
  static bool applySenderDscp(
    RawDatagramSocket? socket,
    int dscp, {
    int ecn = 0,
  }) => applySenderDscpWithResult(socket, dscp, ecn: ecn).success;

  /// Applies IPv4 `IP_TOS` for [preset] on [socket], returning a detailed
  /// [DscpSocketApplyResult].
  static DscpSocketApplyResult applySenderPresetWithResult(
    RawDatagramSocket? socket,
    DscpPreset preset, {
    int ecn = 0,
  }) => applySenderDscpWithResult(socket, preset.dscpValue, ecn: ecn);

  /// Applies IPv4 `IP_TOS` for [preset] on [socket].
  @visibleForTesting
  static bool applySenderPreset(
    RawDatagramSocket? socket,
    DscpPreset preset, {
    int ecn = 0,
  }) => applySenderPresetWithResult(socket, preset, ecn: ecn).success;

  /// Enables `IP_RECVTOS` on [socket], returning a detailed
  /// [DscpSocketApplyResult].
  ///
  /// Never throws when [socket] is `null` or when the host OS rejects
  /// `IP_RECVTOS`.
  static DscpSocketApplyResult enableReceiveTosWithResult(
    RawDatagramSocket? socket,
  ) {
    if (socket == null) {
      return const DscpSocketApplyResult(
        success: false,
        warningMessage: 'Socket is null; IP_RECVTOS was not enabled.',
      );
    }

    final option = buildReceiveTosOption();
    if (option == null) {
      return DscpSocketApplyResult(
        success: false,
        warningMessage:
            'IP_RECVTOS is unsupported on platform "${Platform.operatingSystem}".',
      );
    }

    try {
      socket.setRawOption(option);
      return const DscpSocketApplyResult(success: true);
    } catch (e) {
      return DscpSocketApplyResult(
        success: false,
        warningMessage: 'Failed to enable IP_RECVTOS: $e',
      );
    }
  }

  /// Requests `IP_RECVTOS` delivery metadata on [socket].
  ///
  /// Returns `true` if `setRawOption` succeeded, or `false` if [socket] is
  /// `null` or the OS kernel does not support `IP_RECVTOS`.
  static bool enableReceiveTos(RawDatagramSocket? socket) =>
      enableReceiveTosWithResult(socket).success;

  /// Reads the active `IP_TOS` byte from [socket], or `null` if [socket] is
  /// `null` or `getRawOption` fails.
  @visibleForTesting
  static int? readSocketTos(RawDatagramSocket? socket) {
    if (socket == null) return null;
    final options = currentPlatformOptions;
    if (options == null) return null;

    try {
      final probe = RawSocketOption.fromInt(
        options.level,
        options.ipTosOption,
        0,
      );
      final bytes = socket.getRawOption(probe);
      if (bytes.length >= 4) {
        return ByteData.sublistView(bytes).getInt32(0, Endian.host) & 0xFF;
      }
      if (bytes.isNotEmpty) {
        return bytes[0] & 0xFF;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reads the active 6-bit DSCP value (`0..63`) from [socket], or `null` if
  /// unavailable.
  @visibleForTesting
  static int? readSocketDscp(RawDatagramSocket? socket) {
    final tos = readSocketTos(socket);
    return tos == null ? null : DscpPreset.extractDscpFromTos(tos);
  }
}
