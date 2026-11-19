import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:igmp_tester/ui/widgets/guided_tour_overlay.dart';

void main() {
  Widget buildTestHarness({
    Key? overlayKey,
    required List<GuidedTourStep> steps,
    required VoidCallback onFinish,
    required bool isActive,
    ThemeData? theme,
    Widget? child,
  }) {
    return MaterialApp(
      theme:
          theme ?? ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: GuidedTourOverlay(
          key: overlayKey,
          steps: steps,
          onFinish: onFinish,
          isActive: isActive,
          child: child ?? const SizedBox.expand(),
        ),
      ),
    );
  }

  Container findTooltipCardContainer(WidgetTester tester) {
    final finder = find.ancestor(
      of: find.textContaining('DEMO WALKTHROUGH'),
      matching: find.byType(Container),
    );
    return tester.widget<Container>(finder.at(1));
  }

  Rect getTooltipCardRect(WidgetTester tester) {
    final finder = find.ancestor(
      of: find.textContaining('DEMO WALKTHROUGH'),
      matching: find.byType(Container),
    );
    return tester.getRect(finder.at(1));
  }

  group('GuidedTourOverlay', () {
    testWidgets('inactive state renders child without overlay or tooltip', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final stepKey = GlobalKey();
      var childTapped = false;

      await tester.pumpWidget(
        buildTestHarness(
          isActive: false,
          onFinish: () {},
          steps: [
            GuidedTourStep(
              targetKey: stepKey,
              title: 'Step 1',
              description: 'Step 1 description',
            ),
          ],
          child: Center(
            child: ElevatedButton(
              key: stepKey,
              onPressed: () => childTapped = true,
              child: const Text('Underlying Action'),
            ),
          ),
        ),
      );

      expect(find.text('Underlying Action'), findsOneWidget);
      expect(find.textContaining('DEMO WALKTHROUGH'), findsNothing);
      expect(find.text('End Demo'), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.tap(find.text('Underlying Action'));
      await tester.pump();
      expect(childTapped, isTrue);
    });

    testWidgets('active state with empty steps renders child without overlay', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHarness(
          isActive: true,
          onFinish: () {},
          steps: const [],
          child: const Center(child: Text('Clean Workspace')),
        ),
      );

      expect(find.text('Clean Workspace'), findsOneWidget);
      expect(find.textContaining('DEMO WALKTHROUGH'), findsNothing);
    });

    testWidgets(
      'active walkthrough steps forward, backward, invokes onStepEnter, blocks stray clicks, and finishes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final key1 = GlobalKey();
        final key2 = GlobalKey();
        final key3 = GlobalKey();
        final enteredSteps = <int>[];
        var finishCount = 0;
        var childClicked = false;

        final steps = [
          GuidedTourStep(
            targetKey: key1,
            title: 'Zone 1: Interface',
            description: 'Select the local network adapter.',
            onStepEnter: () => enteredSteps.add(0),
          ),
          GuidedTourStep(
            targetKey: key2,
            title: 'Zone 2: Stream Table',
            description: 'Inspect active multicast Tx and Rx streams.',
            onStepEnter: () async {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              enteredSteps.add(1);
            },
          ),
          GuidedTourStep(
            targetKey: key3,
            title: 'Zone 3: IGMP Sniffer',
            description: 'Monitor IGMP queries and membership reports.',
            onStepEnter: () => enteredSteps.add(2),
          ),
        ];

        await tester.pumpWidget(
          buildTestHarness(
            isActive: true,
            onFinish: () => finishCount++,
            steps: steps,
            child: Stack(
              children: [
                Positioned(
                  left: 24,
                  top: 16,
                  child: SizedBox(
                    key: key1,
                    width: 180,
                    height: 36,
                    child: const Text('Interface Box'),
                  ),
                ),
                Positioned(
                  left: 40,
                  top: 180,
                  child: SizedBox(
                    key: key2,
                    width: 400,
                    height: 160,
                    child: ElevatedButton(
                      onPressed: () => childClicked = true,
                      child: const Text('Streams Panel'),
                    ),
                  ),
                ),
                Positioned(
                  left: 40,
                  bottom: 24,
                  child: SizedBox(
                    key: key3,
                    width: 400,
                    height: 100,
                    child: const Text('Sniffer Panel'),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        // Step 1 verification
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 3'), findsOneWidget);
        expect(find.text('Zone 1: Interface'), findsOneWidget);
        expect(find.text('Select the local network adapter.'), findsOneWidget);
        expect(find.text('End Demo'), findsOneWidget);
        expect(find.text('Back'), findsNothing);
        expect(find.text('Next'), findsOneWidget);
        expect(find.text('Finish & Clear'), findsNothing);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(enteredSteps, [0]);

        // Stray clicks on underlying UI are blocked by the spotlight backdrop
        await tester.tapAt(const Offset(100, 220));
        await tester.pump();
        expect(childClicked, isFalse);

        // Advance to Step 2 via Next
        await tester.tap(find.text('Next'));
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pump();

        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 3'), findsOneWidget);
        expect(find.text('Zone 2: Stream Table'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        expect(enteredSteps, [0, 1]);

        // Go back to Step 1 via Back
        await tester.tap(find.text('Back'));
        await tester.pump();
        await tester.pump();

        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 3'), findsOneWidget);
        expect(find.text('Back'), findsNothing);
        expect(enteredSteps, [0, 1, 0]);

        // Advance to Step 3 via Next twice
        await tester.tap(find.text('Next'));
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pump();
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump();

        expect(find.text('DEMO WALKTHROUGH • STEP 3 OF 3'), findsOneWidget);
        expect(find.text('Zone 3: IGMP Sniffer'), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
        expect(find.text('Next'), findsNothing);
        expect(find.text('Finish & Clear'), findsOneWidget);
        expect(enteredSteps, [0, 1, 0, 1, 2]);

        // Finish via Finish & Clear
        await tester.tap(find.text('Finish & Clear'));
        await tester.pump();
        expect(finishCount, 1);
      },
    );

    testWidgets('exits via End Demo button and top-right close icon', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key1 = GlobalKey();
      final key2 = GlobalKey();
      var finishCount = 0;

      await tester.pumpWidget(
        buildTestHarness(
          isActive: true,
          onFinish: () => finishCount++,
          steps: [
            GuidedTourStep(
              targetKey: key1,
              title: 'Step 1',
              description: 'First step',
            ),
            GuidedTourStep(
              targetKey: key2,
              title: 'Step 2',
              description: 'Second step',
            ),
          ],
          child: Column(
            children: [
              SizedBox(key: key1, width: 100, height: 40),
              SizedBox(key: key2, width: 100, height: 40),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('End Demo'));
      await tester.pump();
      expect(finishCount, 1);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(finishCount, 2);
    });

    testWidgets(
      'keyboard navigation supports ArrowRight, ArrowLeft, Enter, and Escape',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final key1 = GlobalKey();
        final key2 = GlobalKey();
        var finishCount = 0;

        await tester.pumpWidget(
          buildTestHarness(
            isActive: true,
            onFinish: () => finishCount++,
            steps: [
              GuidedTourStep(
                targetKey: key1,
                title: 'First Step',
                description: 'Step one',
              ),
              GuidedTourStep(
                targetKey: key2,
                title: 'Final Step',
                description: 'Step two',
              ),
            ],
            child: Column(
              children: [
                SizedBox(key: key1, width: 120, height: 40),
                SizedBox(key: key2, width: 120, height: 40),
              ],
            ),
          ),
        );
        await tester.pump();

        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 2'), findsOneWidget);

        // ArrowLeft on first step does nothing
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 2'), findsOneWidget);
        expect(finishCount, 0);

        // ArrowRight advances to step 2
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.pump();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 2'), findsOneWidget);

        // ArrowLeft goes back to step 1
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.pump();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 2'), findsOneWidget);

        // Enter advances to step 2
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 2'), findsOneWidget);

        // Enter on final step invokes onFinish
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(finishCount, 1);

        // ArrowRight on final step also invokes onFinish
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(finishCount, 2);

        // Escape invokes onFinish
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(finishCount, 3);
      },
    );

    testWidgets('deactivating and reactivating resets walkthrough to Step 1', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final key1 = GlobalKey();
      final key2 = GlobalKey();
      var isActive = true;

      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return Scaffold(
                body: GuidedTourOverlay(
                  isActive: isActive,
                  onFinish: () => setState(() => isActive = false),
                  steps: [
                    GuidedTourStep(
                      targetKey: key1,
                      title: 'Step One',
                      description: 'Desc 1',
                    ),
                    GuidedTourStep(
                      targetKey: key2,
                      title: 'Step Two',
                      description: 'Desc 2',
                    ),
                  ],
                  child: Column(
                    children: [
                      SizedBox(key: key1, width: 100, height: 32),
                      SizedBox(key: key2, width: 100, height: 32),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump();
      expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 2'), findsOneWidget);

      setHostState(() => isActive = false);
      await tester.pump();
      expect(find.textContaining('DEMO WALKTHROUGH'), findsNothing);

      setHostState(() => isActive = true);
      await tester.pump();
      await tester.pump();
      expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 2'), findsOneWidget);
      expect(find.text('Step One'), findsOneWidget);
    });

    testWidgets(
      'renders crisply with brightness-aware Dark and Light ThemeData colors',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final targetKey = GlobalKey();
        final steps = [
          GuidedTourStep(
            targetKey: targetKey,
            title: 'Theme Aware Title',
            description: 'Theme aware description body.',
          ),
        ];

        // Dark mode verification
        await tester.pumpWidget(
          buildTestHarness(
            theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
            isActive: true,
            onFinish: () {},
            steps: steps,
            child: Center(
              child: SizedBox(key: targetKey, width: 240, height: 48),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        final darkCard = findTooltipCardContainer(tester);
        final darkDecoration = darkCard.decoration! as BoxDecoration;
        expect(darkDecoration.color, const Color(0xFF1E1E1E));
        expect(
          (darkDecoration.border! as Border).top.color,
          const Color(0xFF007ACC),
        );

        final darkBadgeText = tester.widget<Text>(
          find.text('DEMO WALKTHROUGH • STEP 1 OF 1'),
        );
        expect(darkBadgeText.style?.color, const Color(0xFF38BDF8));

        final darkTitleText = tester.widget<Text>(
          find.text('Theme Aware Title'),
        );
        expect(darkTitleText.style?.color, const Color(0xFFE0E0E0));

        final darkBodyText = tester.widget<Text>(
          find.text('Theme aware description body.'),
        );
        expect(darkBodyText.style?.color, const Color(0xFFD4D4D4));

        CustomPainter findSpotlightPainter(WidgetTester tester) {
          final painters = tester.widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(GuidedTourOverlay),
              matching: find.byType(CustomPaint),
            ),
          );
          return painters
              .firstWhere(
                (w) => w.painter.runtimeType.toString() == '_SpotlightPainter',
              )
              .painter!;
        }

        final darkSpotlightPainter = findSpotlightPainter(tester);
        expect(
          darkSpotlightPainter.shouldRepaint(darkSpotlightPainter),
          isFalse,
        );

        // Light mode verification (settle AnimatedTheme transition)
        await tester.pumpWidget(
          buildTestHarness(
            theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
            isActive: true,
            onFinish: () {},
            steps: steps,
            child: Center(
              child: SizedBox(key: targetKey, width: 240, height: 48),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final lightSpotlightPainter = findSpotlightPainter(tester);
        expect(
          lightSpotlightPainter.shouldRepaint(darkSpotlightPainter),
          isTrue,
        );

        final lightCard = findTooltipCardContainer(tester);
        final lightDecoration = lightCard.decoration! as BoxDecoration;
        expect(lightDecoration.color, const Color(0xFFFFFFFF));
        expect(
          (lightDecoration.border! as Border).top.color,
          const Color(0xFFE5E7EB),
        );

        final lightBadgeText = tester.widget<Text>(
          find.text('DEMO WALKTHROUGH • STEP 1 OF 1'),
        );
        expect(lightBadgeText.style?.color, const Color(0xFF0369A1));

        final lightTitleText = tester.widget<Text>(
          find.text('Theme Aware Title'),
        );
        expect(lightTitleText.style?.color, const Color(0xFF111827));

        final lightBodyText = tester.widget<Text>(
          find.text('Theme aware description body.'),
        );
        expect(lightBodyText.style?.color, const Color(0xFF4B5563));
      },
    );

    testWidgets(
      'clamps tooltip card safely inside viewport at 1280x800 and narrower sizes without overflow',
      (WidgetTester tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.devicePixelRatio = 1.0;

        Future<void> verifyBoundsForTarget({
          required Size viewport,
          required Alignment targetAlignment,
          required Size targetSize,
        }) async {
          tester.view.physicalSize = viewport;
          final k1 = GlobalKey();
          final k2 = GlobalKey();
          final k3 = GlobalKey();

          await tester.pumpWidget(
            buildTestHarness(
              overlayKey: UniqueKey(),
              isActive: true,
              onFinish: () {},
              steps: [
                GuidedTourStep(
                  targetKey: k1,
                  title: 'Step 1',
                  description: 'First step targeting edge alignment.',
                ),
                GuidedTourStep(
                  targetKey: k2,
                  title: 'Step 2 With Back And Next Buttons',
                  description: 'Verifies multi-button row never overflows at narrow viewport widths.',
                ),
                GuidedTourStep(
                  targetKey: k3,
                  title: 'Step 3 With Finish & Clear',
                  description: 'Verifies final step button layout and bounds.',
                ),
              ],
              child: Align(
                alignment: targetAlignment,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      key: k1,
                      width: targetSize.width,
                      height: targetSize.height / 3,
                    ),
                    SizedBox(
                      key: k2,
                      width: targetSize.width,
                      height: targetSize.height / 3,
                    ),
                    SizedBox(
                      key: k3,
                      width: targetSize.width,
                      height: targetSize.height / 3,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);

          final viewportRect = Offset.zero & viewport;
          final step1Rect = getTooltipCardRect(tester);
          expect(viewportRect.contains(step1Rect.topLeft), isTrue);
          expect(viewportRect.contains(step1Rect.bottomRight), isTrue);

          // Advance to step 2 (shows End Demo, Back, Next)
          await tester.tap(find.text('Next'));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);

          final step2Rect = getTooltipCardRect(tester);
          expect(viewportRect.contains(step2Rect.topLeft), isTrue);
          expect(viewportRect.contains(step2Rect.bottomRight), isTrue);

          // Advance to step 3 (shows End Demo, Back, Finish & Clear)
          await tester.tap(find.text('Next'));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);

          final step3Rect = getTooltipCardRect(tester);
          expect(viewportRect.contains(step3Rect.topLeft), isTrue);
          expect(viewportRect.contains(step3Rect.bottomRight), isTrue);
        }

        // Standard desktop 1280x800: top-left, far-right, bottom, and full panel
        await verifyBoundsForTarget(
          viewport: const Size(1280, 800),
          targetAlignment: Alignment.topLeft,
          targetSize: const Size(200, 120),
        );
        await verifyBoundsForTarget(
          viewport: const Size(1280, 800),
          targetAlignment: Alignment.topRight,
          targetSize: const Size(180, 120),
        );
        await verifyBoundsForTarget(
          viewport: const Size(1280, 800),
          targetAlignment: Alignment.bottomRight,
          targetSize: const Size(220, 120),
        );
        await verifyBoundsForTarget(
          viewport: const Size(1280, 800),
          targetAlignment: Alignment.center,
          targetSize: const Size(1280, 750),
        );

        // Narrower viewports
        await verifyBoundsForTarget(
          viewport: const Size(420, 600),
          targetAlignment: Alignment.bottomCenter,
          targetSize: const Size(380, 120),
        );
        await verifyBoundsForTarget(
          viewport: const Size(320, 480),
          targetAlignment: Alignment.topCenter,
          targetSize: const Size(300, 90),
        );
        await verifyBoundsForTarget(
          viewport: const Size(280, 360),
          targetAlignment: Alignment.center,
          targetSize: const Size(260, 240),
        );
      },
    );
  });
}
