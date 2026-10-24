import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/main.dart';

void main() {
  testWidgets('IgmpTesterApp desktop smoke test and tab rendering', (WidgetTester tester) async {
    // Set standard desktop window dimensions
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const IgmpTesterApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Verify app title and tab labels
    expect(find.text('IGMP & Multicast Tester'), findsOneWidget);
    expect(find.text('Transmitter (Tx)'), findsOneWidget);
    expect(find.text('Receiver (Rx)'), findsOneWidget);
    expect(find.text('START TRANSMITTING MULTICAST STREAM'), findsOneWidget);

    // Switch to Receiver Tab (TabBar animation takes ~300ms)
    await tester.tap(find.text('Receiver (Rx)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('JOIN MULTICAST GROUP & START RECEIVING'), findsOneWidget);
    expect(find.text('Packets Received'), findsOneWidget);
    expect(find.text('Packet Loss Rate'), findsOneWidget);
  });
}
