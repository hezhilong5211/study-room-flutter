import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:study_room_flutter/domain.dart';

void main() {
  late DateTime time;
  late StudyStore store;
  setUp(() {
    time = DateTime.utc(2026, 10, 17, 8);
    store = StudyStore.demo(clock: () => time);
  });
  tearDown(() => store.dispose());

  test(
    'guest registration and profile completion separately gate room creation',
    () {
      store.switchUser('guest');
      expect(() => store.createRoom(name: '访客房间'), throwsStateError);
      store.registerGuest(name: '小明');
      expect(store.currentUser.isGuest, isFalse);
      expect(() => store.createRoom(name: '未完善资料'), throwsStateError);
      store.updateProfile(name: '小明', avatar: '书');
      final room = store.createRoom(name: '我的自习室');
      expect(room.ownerId, 'guest');
      expect(room.residents.single.approved, isTrue);
      expect(() => store.createRoom(name: '  '), throwsStateError);
      store.switchUser('new');
      expect(() => store.createRoom(name: '未完善'), throwsStateError);
    },
  );

  test(
    'badge issuer and recipient lists, code redemption, expiry and renewal',
    () {
      final badge = store.createBadge(
        name: '阅读计划',
        validity: const Duration(hours: 1),
      );
      expect(store.issuedBadges, contains(badge));
      expect(store.receivedBadges, contains(badge));
      store.switchUser('chen');
      store.redeemBadge(' ${badge.code.toLowerCase()} ');
      store.redeemBadge(badge.code);
      expect(badge.recipientIds, {'lin', 'chen'});
      expect(store.receivedBadges, contains(badge));
      expect(() => store.revokeBadge(badge.id), throwsStateError);
      expect(() => store.renewBadge(badgeId: badge.id), throwsStateError);
      time = time.add(const Duration(hours: 1));
      expect(store.ownsBadge('chen', badge.id), isFalse);
      expect(() => store.redeemBadge(badge.code), throwsStateError);
      store.switchUser('lin');
      store.renewBadge(badgeId: badge.id, validity: const Duration(days: 1));
      expect(store.ownsBadge('chen', badge.id), isTrue);
      final previous = badge.expiresAt!;
      store.renewBadge(badgeId: badge.id, validity: const Duration(days: 1));
      expect(badge.expiresAt, previous.add(const Duration(days: 1)));
      store.renewBadge(badgeId: badge.id);
      expect(badge.isLifetime, isTrue);
      store.revokeBadge(badge.id);
      expect(store.ownsBadge('chen', badge.id), isFalse);
      expect(() => store.renewBadge(badgeId: badge.id), throwsStateError);
      expect(() => store.redeemBadge('unknown'), throwsStateError);
      expect(
        () => store.createBadge(name: '错误', validity: Duration.zero),
        throwsStateError,
      );
    },
  );

  test('badge gate applies to creators and public/private entrants', () {
    final badge = store.createBadge(name: '邀请徽章');
    final public = store.createRoom(name: '徽章公开房', requiredBadgeId: badge.id);
    final private = store.createRoom(
      name: '徽章私密房',
      isPrivate: true,
      requiredBadgeId: badge.id,
    );
    store.switchUser('chen');
    expect(
      () => store.createRoom(name: '无资格', requiredBadgeId: badge.id),
      throwsStateError,
    );
    expect(() => store.requestJoinRoom(public.id), throwsStateError);
    expect(() => store.requestJoinRoom(private.id), throwsStateError);
    store.redeemBadge(badge.code);
    store.requestJoinRoom(public.id);
    expect(store.residentOf(public, 'chen')!.isOnline, isFalse);
    expect(store.residentOf(public, 'chen')!.approved, isFalse);
    store.requestJoinRoom(private.id);
    expect(store.residentOf(private, 'chen')!.approved, isFalse);
    expect(
      () => store.setResidentOnline(roomId: private.id, online: true),
      throwsStateError,
    );
  });

  test(
    'private approval persists across offline presence and user switching',
    () {
      final room = store.createRoom(name: '私密房', isPrivate: true);
      store.switchUser('chen');
      store.requestJoinRoom(room.id);
      expect(
        () => store.approveResident(roomId: room.id, userId: 'chen'),
        throwsStateError,
      );
      store.switchUser('lin');
      store.approveResident(roomId: room.id, userId: 'chen');
      store.switchUser('chen');
      store.setResidentOnline(roomId: room.id, online: true);
      time = time.add(const Duration(minutes: 25));
      store.leaveRoom(room.id);
      final resident = store.residentOf(room, 'chen')!;
      expect(resident.approved, isTrue);
      expect(resident.isOnline, isFalse);
      expect(resident.lastSeen, time);
      store.switchUser('zhou');
      store.switchUser('chen');
      store.requestJoinRoom(room.id);
      expect(resident.isOnline, isTrue);
      expect(room.residents.where((r) => r.userId == 'chen').length, 1);
    },
  );

  test(
    'ordered eligible admin succeeds even offline; otherwise room dissolves',
    () {
      final room = store.createRoom(name: '传承自习室');
      for (final id in ['chen', 'zhou']) {
        store.switchUser(id);
        store.requestJoinRoom(room.id);
        store.switchUser('lin');
        store.approveResident(roomId: room.id, userId: id);
        store.switchUser(id);
        store.setResidentOnline(roomId: room.id, online: true);
        store.leaveRoom(room.id);
      }
      store.switchUser('lin');
      store.addAdmin(roomId: room.id, userId: 'chen');
      store.addAdmin(roomId: room.id, userId: 'zhou');
      expect(
        () => store.reorderAdmins(roomId: room.id, userIds: ['chen', 'chen']),
        throwsStateError,
      );
      store.reorderAdmins(roomId: room.id, userIds: ['zhou', 'chen']);
      store.userById('lin').profileComplete = false;
      store.sweep();
      expect(room.ownerId, 'zhou');
      expect(room.adminIds, ['chen']);
      expect(store.residentOf(room, 'zhou')!.isOnline, isFalse);
      store.userById('zhou').profileComplete = false;
      store.sweep();
      expect(room.ownerId, 'chen');
      store.userById('chen').profileComplete = false;
      store.sweep();
      expect(store.rooms, isNot(contains(room)));
    },
  );

  test(
    'public residency requires owner consent and cannot be approved by admins',
    () {
      final room = store.rooms.first;
      store.switchUser('guest');
      final publicRoomId = store.rooms
          .firstWhere((r) => r.requiredBadgeId == null && !r.isPrivate)
          .id;
      store.requestJoinRoom(publicRoomId);
      expect(
        store.residentOf(store.roomById(publicRoomId), 'guest')!.approved,
        isFalse,
      );
      expect(
        () => store.setResidentOnline(roomId: publicRoomId, online: true),
        throwsStateError,
      );
      store.switchUser('chen');
      store.approveResident(roomId: publicRoomId, userId: 'guest');
      store.switchUser('guest');
      store.setResidentOnline(roomId: publicRoomId, online: true);
      store.leaveRoom(publicRoomId);
      expect(
        store.residentOf(store.roomById(publicRoomId), 'guest')!.approved,
        isTrue,
      );
      store.switchUser('lin');
      store.redeemBadge(store.badgeById(room.requiredBadgeId!).code);
      store.switchUser('new');
      store.redeemBadge(store.badgeById(room.requiredBadgeId!).code);
      store.requestJoinRoom(room.id);
      store.switchUser('chen');
      expect(room.adminIds, contains('chen'));
      expect(
        () => store.approveResident(roomId: room.id, userId: 'new'),
        throwsStateError,
      );
      store.switchUser('lin');
      store.approveResident(roomId: room.id, userId: 'new');
      expect(store.residentOf(room, 'new')!.approved, isTrue);
    },
  );

  test('recipient revocation is issuer-only and removes recipient without revoking others', () {
    final badge = store.badges.first;
    store.switchUser('chen');
    expect(
      () => store.revokeBadgeRecipient(badge.id, 'zhou'),
      throwsStateError,
    );
    expect(badge.recipientIds, contains('zhou'));
    store.switchUser('lin');
    var notifications = 0;
    store.addListener(() => notifications++);
    store.revokeBadgeRecipient(badge.id, 'chen');
    expect(badge.recipientIds, isNot(contains('chen')));
    expect(badge.revoked, isFalse);
    expect(store.ownsBadge('zhou', badge.id), isTrue);
    expect(store.rooms.first.ownerId, 'lin');
    expect(store.rooms.first.adminIds, isNot(contains('chen')));
    expect(store.residentOf(store.rooms.first, 'chen')!.isOnline, isFalse);
    expect(notifications, greaterThan(0));
    expect(
      () => store.revokeBadgeRecipient(badge.id, 'missing'),
      throwsStateError,
    );
  });

  test('succession skips an ineligible first admin and selects the next offline admin', () {
    final room = store.rooms.first;
    store.userById('chen').profileComplete = false;
    store.revokeBadgeRecipient(room.requiredBadgeId!, 'lin');
    expect(room.ownerId, 'zhou');
    expect(room.adminIds, isEmpty);
    expect(store.residentOf(room, 'zhou')!.isOnline, isFalse);
    expect(store.residentOf(room, 'lin')!.isOnline, isFalse);
  });

  test('recipient badge revocation transfers a gated room in admin order', () {
    final room = store.rooms.firstWhere((r) => r.requiredBadgeId != null);
    final badge = store.badgeById(room.requiredBadgeId!);
    store.reorderAdmins(roomId: room.id, userIds: ['zhou', 'chen']);
    store.revokeBadgeRecipient(badge.id, 'lin');
    expect(room.ownerId, 'zhou');
    expect(store.residentOf(room, 'lin')!.isOnline, isFalse);
    expect(store.ownsBadge('chen', badge.id), isTrue);
    expect(store.residentOf(room, 'lin')!.approved, isTrue);
    // The issuer keeps management of the issued badge after losing ownership.
    store.revokeBadgeRecipient(badge.id, 'zhou');
    expect(room.ownerId, 'chen');
    store.revokeBadgeRecipient(badge.id, 'chen');
    expect(store.rooms, isNot(contains(room)));
  });

  test(
    'revocation and exact expiry dissolve rooms with invalid badge gate',
    () {
      final badge = store.createBadge(
        name: '限时',
        validity: const Duration(minutes: 5),
      );
      final room = store.createRoom(name: '限时房', requiredBadgeId: badge.id);
      store.switchUser('chen');
      store.redeemBadge(badge.code);
      store.requestJoinRoom(room.id);
      store.switchUser('lin');
      store.approveResident(roomId: room.id, userId: 'chen');
      store.addAdmin(roomId: room.id, userId: 'chen');
      time = badge.expiresAt!;
      store.sweep();
      expect(store.rooms, isNot(contains(room)));
      final forever = store.createBadge(name: '长期');
      final other = store.createRoom(name: '撤销房', requiredBadgeId: forever.id);
      store.revokeBadge(forever.id);
      expect(store.rooms, isNot(contains(other)));
    },
  );

  test('management permission, fixed ambience and emoji presence rules', () {
    final room = store.createRoom(name: '环境测试');
    final event = store.sendEmoji(roomId: room.id, emoji: '👍');
    expect(event.userId, 'lin');
    expect(event.createdAt, time);
    store.updateRoomAmbience(
      roomId: room.id,
      backgroundId: 'forest',
      musicId: 'piano',
      emojiEnabled: false,
    );
    expect(room.backgroundId, 'forest');
    expect(room.musicId, 'piano');
    expect(
      () => store.sendEmoji(roomId: room.id, emoji: '👍'),
      throwsStateError,
    );
    expect(
      () => store.updateRoomAmbience(roomId: room.id, backgroundId: 'unknown'),
      throwsStateError,
    );
    store.updateRoomAmbience(roomId: room.id, emojiEnabled: true);
    store.switchUser('chen');
    expect(
      () => store.updateRoomAmbience(roomId: room.id, musicId: 'silent'),
      throwsStateError,
    );
    expect(
      () => store.sendEmoji(roomId: room.id, emoji: '👍'),
      throwsStateError,
    );
    store.requestJoinRoom(room.id);
    store.switchUser('lin');
    store.approveResident(roomId: room.id, userId: 'chen');
    store.switchUser('chen');
    store.setResidentOnline(roomId: room.id, online: true);
    store.sendEmoji(roomId: room.id, emoji: '加油');
    store.leaveRoom(room.id);
    expect(
      () => store.sendEmoji(roomId: room.id, emoji: '👍'),
      throwsStateError,
    );
  });

  test(
    'friend acceptance is recipient-only, symmetric, and blocks duplicates',
    () {
      final request = store.sendFriendRequest('zhou');
      expect(() => store.sendFriendRequest('zhou'), throwsStateError);
      expect(() => store.acceptFriendRequest(request.id), throwsStateError);
      store.switchUser('zhou');
      expect(() => store.sendFriendRequest('lin'), throwsStateError);
      store.acceptFriendRequest(request.id);
      expect(store.currentUser.friendIds, contains('lin'));
      expect(store.userById('lin').friendIds, contains('zhou'));
      expect(() => store.acceptFriendRequest(request.id), throwsStateError);
      expect(() => store.sendFriendRequest('lin'), throwsStateError);
      final other = store.sendFriendRequest('chen');
      store.switchUser('chen');
      store.declineFriendRequest(other.id);
      expect(other.status, 'declined');
      expect(store.currentUser.friendIds, isNot(contains('zhou')));
      expect(() => store.sendFriendRequest('chen'), throwsStateError);
    },
  );

  test('paid gift waits for recipient acceptance; frames switch and expire independently', () {
    final gift = store.purchaseGift(
      recipientId: 'chen',
      frameId: 'blossom',
      duration: const Duration(days: 1),
    );
    expect(gift.status, 'paid');
    expect(gift.expiresAt, isNull);
    expect(() => store.acceptGift(gift.id), throwsStateError);
    time = time.add(const Duration(days: 10));
    store.switchUser('chen');
    store.acceptGift(gift.id);
    expect(gift.activatedAt, time);
    expect(gift.expiresAt, time.add(const Duration(days: 1)));
    expect(store.currentUser.activeFrameId, 'blossom');
    expect(() => store.acceptGift(gift.id), throwsStateError);
    store.switchUser('lin');
    final second = store.purchaseGift(
      recipientId: 'chen',
      frameId: 'laurel',
      duration: const Duration(days: 2),
    );
    store.switchUser('chen');
    store.acceptGift(second.id);
    expect(store.activeFrames.length, 2);
    store.switchFrame(gift.id);
    expect(store.currentUser.activeFrameId, 'blossom');
    store.switchFrame(null);
    expect(store.currentUser.activeFrameId, isNull);
    store.switchFrame(second.id);
    time = time.add(const Duration(days: 1));
    store.sweep();
    expect(gift.status, 'expired');
    expect(store.currentUser.activeFrameId, 'laurel');
    expect(() => store.switchFrame(gift.id), throwsStateError);
    time = time.add(const Duration(days: 1));
    store.sweep();
    expect(store.currentUser.activeFrameId, isNull);
    expect(store.activeFrames, isEmpty);
  });

  test(
    'JSON round trip retains domain and rejects malformed snapshots atomically',
    () {
      final snapshot = store.exportJson();
      final restored = StudyStore(clock: () => time);
      addTearDown(restored.dispose);
      restored.importJson(snapshot);
      expect(jsonDecode(restored.exportJson()), jsonDecode(snapshot));
      expect(restored.currentUser.id, 'lin');
      expect(restored.rooms.first.residents[1].isOnline, isTrue);
      final broken = jsonDecode(snapshot) as Map<String, dynamic>;
      broken['currentUserId'] = 'missing';
      expect(() => restored.importJson(jsonEncode(broken)), throwsStateError);
      expect(restored.exportJson(), snapshot);
      final badge = restored.createBadge(name: '恢复后的新徽章');
      expect(store.badges.any((b) => b.id == badge.id), isFalse);
      time = time.add(const Duration(days: 31));
      restored.importJson(snapshot);
      expect(restored.rooms.any((r) => r.requiredBadgeId != null), isFalse);
    },
  );

  test('store notifies listeners on changes and stable sweep is silent', () {
    var count = 0;
    store.addListener(() => count++);
    store.sweep();
    expect(count, 0);
    store.createRoom(name: '通知');
    expect(count, greaterThan(0));
    final previous = count;
    store.sweep();
    expect(count, previous);
  });
}
