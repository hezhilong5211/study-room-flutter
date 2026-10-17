import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_flutter/main.dart';
import 'package:study_room_flutter/domain.dart';

void main() {
  for (final size in [const Size(375, 667), const Size(320, 568)]) {
    testWidgets('mobile navigation, room presence and sheets at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = StudyStore.demo();
      final room = store.rooms.first;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: StudyApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('我加入的房间'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-search')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的勋章与礼物'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paper-sheet')), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('room-${room.id}')));
      await tester.pumpAndSettle();
      expect(store.residentOf(room, store.currentUser.id)!.isOnline, isTrue);
      if (const bool.fromEnvironment('CAPTURE_UX') && size.width == 375) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${Directory.systemTemp.path}/study-flutter-room.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.byKey(const ValueKey('nav-0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('all-members')));
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('immersive')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-members')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('exit-immersive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('开始专注'));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('暂停专注'));
      expect(store.residentOf(room, store.currentUser.id)!.isOnline, isTrue);
      await tester.tap(find.byTooltip('返回房间列表'));
      await tester.pumpAndSettle();
      expect(store.residentOf(room, store.currentUser.id)!.isOnline, isFalse);
      expect(store.residentOf(room, store.currentUser.id)!.approved, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
