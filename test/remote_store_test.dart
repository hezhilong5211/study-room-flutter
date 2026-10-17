import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_room_flutter/remote_store.dart';

Map<String, dynamic> snapshot() => {
  'serverTime': 1800000000,
  'me': {'id': 'me', 'name': '我', 'isGuest': false, 'profileComplete': true},
  'badges': [
    for (final id in ['a', 'b'])
      {'id': id, 'name': id, 'issuerId': 'issuer', 'revoked': false, 'expiresAt': null},
  ],
  'holdings': [
    {'badgeId': 'a', 'userId': 'me', 'expiresAt': 1800001000, 'revoked': false},
    {'badgeId': 'b', 'userId': 'me', 'expiresAt': 1799999999, 'revoked': false},
  ],
};

void main() {
  test('real HTTP server supports account, rooms, badges, presence, friends and pending orders', () async {
    final directory = await Directory.systemTemp.createTemp('study-http-');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final server = await Process.start('python3', ['-u', 'server/app.py', '--port', '$port', '--db', '${directory.path}/study.sqlite']);
    final errors = <String>[];
    server.stderr.transform(utf8.decoder).listen(errors.add);
    addTearDown(() async {
      server.kill();
      await server.exitCode;
      await directory.delete(recursive: true);
    });
    await server.stdout.transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds: 10));
    final owner = RemoteStudyStore(baseUrl: 'http://127.0.0.1:$port');
    final visitor = RemoteStudyStore(baseUrl: 'http://127.0.0.1:$port');
    addTearDown(owner.dispose);
    addTearDown(visitor.dispose);
    await owner.connect();
    expect(owner.ready, isTrue, reason: '${owner.error} $errors');
    final guestId = owner.currentUser.id;
    await owner.authenticate(register: true, login: 'owner', password: 'owner-password', name: '房主');
    expect(owner.currentUser.id, guestId);
    await owner.updateProfile(name: '房主', avatar: '学');
    final badge = await owner.createBadge(name: '自习勋章', validity: const Duration(days: 30));
    await owner.createBadge(name: '第二勋章');
    final room = await owner.createRoom(name: '真实房间', requiredBadgeId: badge.id);
    await visitor.connect();
    await visitor.authenticate(register: true, login: 'visitor', password: 'visitor-password', name: '同学');
    await visitor.updateProfile(name: '同学', avatar: '学');
    await visitor.redeemBadge(badge.code);
    expect(visitor.ownsBadge(visitor.currentUser.id, badge.id), isTrue);
    await visitor.requestJoinRoom(room.id);
    await owner.poll();
    await owner.approveResident(roomId: room.id, userId: visitor.currentUser.id);
    await visitor.setResidentOnline(roomId: room.id, online: true);
    await visitor.sendEmoji(roomId: room.id, emoji: '好');
    await owner.setResidentOnline(roomId: room.id, online: true);
    await owner.poll();
    expect(owner.emojiEvents.single.emoji, '好');
    expect(owner.residentOf(owner.roomById(room.id), visitor.currentUser.id)!.isOnline, isTrue);
    await visitor.sendFriendRequest(owner.currentUser.id);
    await owner.poll();
    await owner.acceptFriendRequest(owner.friendRequests.single.id);
    expect(owner.currentUser.friendIds, contains(visitor.currentUser.id));
    final order = await owner.purchaseGift(recipientId: visitor.currentUser.id, frameId: 'starlight', duration: const Duration(days: 7));
    expect(order.status, 'pending');
    await visitor.poll();
    await expectLater(visitor.acceptGift(order.id), throwsStateError);
    await owner.revokeBadgeRecipient(badge.id, visitor.currentUser.id);
    await visitor.poll();
    expect(visitor.ownsBadge(visitor.currentUser.id, badge.id), isFalse);
    expect(visitor.holding(badge.id, visitor.currentUser.id)!['revoked'], isTrue);
    await owner.logout();
    await owner.authenticate(register: false, login: 'owner', password: 'owner-password');
    expect(owner.currentUser.id, guestId);
  });
  test('redacted codes coexist and personal expiry gates ownership without hiding history', () {
    final store = RemoteStudyStore(baseUrl: 'http://test');
    addTearDown(store.dispose);
    store.applyServerState(snapshot());
    expect(store.badges.length, 2);
    expect(store.receivedBadges.length, 2);
    expect(store.ownsBadge('me', 'a'), isTrue);
    expect(store.ownsBadge('me', 'b'), isFalse);
    expect(store.holding('a', 'me')!['expiresAt'], 1800001000);
  });

  test('guest upgrade preserves bearer and subsequent errors do not poison queue', () async {
    final calls = <String>[];
    var fail = true;
    final client = MockClient((request) async {
      calls.add(request.url.path);
      if (request.url.path == '/api/auth/guest') return http.Response('{"token":"guest-token"}', 200);
      if (request.url.path == '/api/auth/register') {
        expect(request.headers['Authorization'], 'Bearer guest-token');
        expect(jsonDecode(request.body)['login'], 'alice');
        return http.Response('{"token":"user-token"}', 200);
      }
      if (request.url.path == '/api/action' && fail) {
        fail = false;
        return http.Response(jsonEncode({'error': 'denied'}), 403);
      }
      return http.Response(jsonEncode(snapshot()), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final store = RemoteStudyStore(baseUrl: 'http://test', client: client);
    addTearDown(store.dispose);
    await store.connect();
    await store.authenticate(register: true, login: 'alice', password: 'password123', name: 'Alice');
    await expectLater(store.command('profile'), throwsStateError);
    await store.command('profile');
    expect(store.ready, isTrue);
    expect(calls.where((p) => p == '/api/auth/guest').length, 1);
  });

  test('unconfigured checkout remains pending and cannot become active locally', () {
    final state = snapshot();
    state['orders'] = [
      {'id': 'order', 'senderId': 'issuer', 'recipientId': 'me', 'frameId': 'starlight',
        'durationDays': 7, 'status': 'pending', 'expiresAt': null},
    ];
    final store = RemoteStudyStore(baseUrl: 'http://test');
    addTearDown(store.dispose);
    store.applyServerState(state);
    store.sweep();
    expect(store.gifts.single.status, 'pending');
    expect(store.activeFrames, isEmpty);
  });
}
