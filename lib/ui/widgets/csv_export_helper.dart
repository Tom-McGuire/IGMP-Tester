import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../features/dashboard/view_models/igmp_tester_view_model.dart';
import '../theme/app_theme.dart';

void _showErrorSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: AppTheme.error,
    ),
  );
}

Future<void> _copyPayloadWithFeedback(
  BuildContext context, {
  required String Function() buildPayload,
  required String successMessage,
}) async {
  try {
    final payload = buildPayload();
    await Clipboard.setData(ClipboardData(text: payload));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      _showErrorSnackBar(context, 'Copy failed: $e');
    }
  }
}

/// Prompts the user to save the gap report CSV via [FilePicker.saveFile] and
/// displays a success or error [SnackBar].
Future<void> exportGapsCsvWithFeedback(
  BuildContext context,
  IgmpTesterViewModel vm, {
  String dialogTitle = 'Save Multicast Gap Analysis CSV',
  String filePrefix = 'multicast_gaps',
}) async {
  try {
    final defaultFileName =
        '${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final csvContent = vm.generateGapsCsvContent();
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: defaultFileName,
      bytes: Uint8List.fromList(utf8.encode(csvContent)),
    );
    if (uri != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Gap report saved successfully.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      _showErrorSnackBar(context, 'Export failed: $e');
    }
  }
}

/// Copies the current gap report CSV to the system clipboard with [SnackBar] feedback.
Future<void> copyGapsCsvToClipboard(
  BuildContext context,
  IgmpTesterViewModel vm,
) {
  return _copyPayloadWithFeedback(
    context,
    buildPayload: vm.generateGapsCsvContent,
    successMessage: 'Gaps CSV copied to clipboard',
  );
}

/// Serializes `vm.igmpEvents` as pretty-printed JSON and copies it to the clipboard.
Future<void> copyIgmpLogJsonToClipboard(
  BuildContext context,
  IgmpTesterViewModel vm,
) {
  final count = vm.igmpEvents.length;
  return _copyPayloadWithFeedback(
    context,
    buildPayload: () => const JsonEncoder.withIndent('  ')
        .convert(vm.igmpEvents.map((e) => e.toMap()).toList()),
    successMessage: 'Copied $count IGMP log event(s) as JSON',
  );
}
