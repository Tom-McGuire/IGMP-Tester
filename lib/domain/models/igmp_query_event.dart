class IgmpQueryEvent {
  final DateTime timestamp;
  final String querierIp;
  final String destinationIp;
  final String typeHex;
  final String typeName;
  final String groupAddress;
  final double maxRespTimeSeconds;
  final String version;
  final String interfaceName;
  final String rawSummary;

  const IgmpQueryEvent({
    required this.timestamp,
    required this.querierIp,
    required this.destinationIp,
    required this.typeHex,
    required this.typeName,
    required this.groupAddress,
    required this.maxRespTimeSeconds,
    required this.version,
    required this.interfaceName,
    required this.rawSummary,
  });

  bool get isQuery =>
      typeHex == '0x11' ||
      typeName.toLowerCase().contains('query');

  bool get isGeneralQuery =>
      isQuery && (groupAddress == '0.0.0.0' || destinationIp == '224.0.0.1');

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'querierIp': querierIp,
      'destinationIp': destinationIp,
      'typeHex': typeHex,
      'typeName': typeName,
      'groupAddress': groupAddress,
      'maxRespTimeSeconds': maxRespTimeSeconds,
      'version': version,
      'interfaceName': interfaceName,
      'rawSummary': rawSummary,
    };
  }
}
