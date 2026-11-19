import 'package:material_ui/material_ui.dart';
import '../../domain/models/multicast_config.dart';

/// Returns the Material icon associated with a protocol [category] label.
IconData iconForProtocolCategory(
  String category, {
  IconData defaultIcon = Icons.tune,
}) {
  switch (category) {
    case 'Lighting':
      return Icons.lightbulb_outline;
    case 'Audio':
      return Icons.volume_up_outlined;
    case 'Video':
      return Icons.videocam_outlined;
    case 'Timing':
      return Icons.schedule_outlined;
    default:
      return defaultIcon;
  }
}

/// Returns the Material icon corresponding to [preset]'s protocol category.
IconData iconForProtocolPreset(ProtocolPreset preset) =>
    iconForProtocolCategory(preset.category);
