import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'domain.dart';

/// Server-authoritative adapter. Local StudyStore remains useful for fixtures.
class RemoteStudyStore extends StudyStore {
  RemoteStudyStore({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  String? _token;
  String? error;
  bool ready = false;
  bool _disposed = false;
  Timer? _poll;
  Future<void> _queue = Future.value();
  String? _activeRoom;
  List<Map<String, dynamic>> resources = [];
  String role = 'user';
  List<Map<String, dynamic>> holdings = [];
  DateTime _serverNow = DateTime.now();
  DateTime _receivedAt = DateTime.now();
  @override
  DateTime get now => _serverNow.add(DateTime.now().difference(_receivedAt));

  Map<String, dynamic>? holding(String badgeId, String userId) => holdings
      .where((h) => h['badgeId'] == badgeId && h['userId'] == userId).firstOrNull;

  @override
  List<StudyBadge> get receivedBadges => badges.where((b) =>
      holding(b.id, currentUser.id) != null).toList();

  @override
  bool ownsBadge(String userId, String badgeId) {
    final h = holding(badgeId, userId);
    return badgeById(badgeId).isValidAt(now) && h != null &&
        h['revoked'] != true && (h['expiresAt'] == null ||
        (h['expiresAt'] as num) * 1000 > now.millisecondsSinceEpoch);
  }

  Future<void> renewHolding(String badgeId, String userId) async {
    await command('holding.renew', {'badgeId': badgeId, 'userId': userId, 'days': 30});
  }

  Future<void> rejectResident(String roomId, String userId) async {
    await command('room.review', {'roomId': roomId, 'userId': userId, 'status': 'rejected'});
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, dynamic>> _request(String path, [Map<String, dynamic>? body]) async {
    try {
      final uri = Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
      final response = await (body == null
          ? _client.get(uri, headers: headers)
          : _client.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 15));
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        throw StateError(value is Map ? '${value['error'] ?? '请求失败'}' : '请求失败 (${response.statusCode})');
      }
      if (value is! Map<String, dynamic>) throw const FormatException();
      return value;
    } on StateError {
      rethrow;
    } on TimeoutException {
      throw StateError('连接超时，请检查网络后重试');
    } on FormatException {
      throw StateError('服务器响应格式错误，请检查服务地址');
    } catch (_) {
      throw StateError('无法连接服务器，请检查网络和服务地址');
    }
  }

  // Tokens stay in memory: no credentials or snapshots in local preferences.
  Future<void> connect() => _serial(() async {
    try {
      _token ??= (await _request('/api/auth/guest', {}))['token'] as String;
      await _refresh();
      _poll ??= Timer.periodic(const Duration(seconds: 5), (_) => unawaited(poll()));
    } catch (e) {
      error = e is StateError ? e.message : '$e';
      _notify();
    }
  });

  Future<void> authenticate({required bool register, required String login,
      required String password, String name = ''}) => _serial(() async {
    final result = await _request('/api/auth/${register ? 'register' : 'login'}', {
      'login': login, 'password': password, if (register) 'name': name,
    });
    _token = result['token'] as String;
    _activeRoom = null;
    await _refresh();
  });

  Future<void> logout() => _serial(() async {
    await _request('/api/auth/logout', {});
    _token = null;
    _activeRoom = null;
    ready = false;
    _token = (await _request('/api/auth/guest', {}))['token'] as String;
    await _refresh();
  });

  bool _polling = false;
  Future<void> poll() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      await _serial(() async {
        if (_activeRoom != null) {
          try {
            await _request('/api/action', {'op': 'room.heartbeat', 'roomId': _activeRoom});
          } catch (_) {
            // Refresh revoked access; keep retrying after transient network errors.
            await _refresh();
            final room = rooms.where((r) => r.id == _activeRoom).firstOrNull;
            if (room == null || residentOf(room, currentUser.id)?.isOnline != true) {
              _activeRoom = null;
            }
            rethrow;
          }
        }
        await _refresh();
      });
    } catch (e) {
      error = e is StateError ? e.message : '$e';
      _notify();
    } finally {
      _polling = false;
    }
  }

  void _notify() { if (!_disposed) notifyListeners(); }
  @override
  void sweep() {} // Only the server may expire, transfer or dissolve entities.
  @override
  Future<void> switchUser(String userId) async => throw StateError('请通过账号密码登录');
  @override
  Future<StudyUser> registerGuest({required String name}) async => throw StateError('请填写账号密码注册');

  Future<Map<String, dynamic>> command(String op, [Map<String, dynamic> args = const {}]) => _serial(() async {
    if (!ready) throw StateError('尚未连接服务器，请重试连接');
    final result = await _request('/api/action', {'op': op, ...args});
    // Do not acknowledge a mutation before its authoritative snapshot is loaded.
    try {
      await _refresh();
    } catch (_) {
      error = '操作已提交，但刷新失败；请刷新确认结果，避免重复提交';
      _notify();
      throw StateError(error!);
    }
    return result;
  });

  Future<void> _refresh() async {
    final state = await _request('/api/state');
    applyServerState(state);
    ready = true;
    error = null;
    _notify();
  }

  /// Maps the REST projection to existing seasonal UI entities, without local
  /// authorization/succession changes. Missing public names get an ID label.
  void applyServerState(Map<String, dynamic> state) {
    List<Map<String, dynamic>> list(String key) => (state[key] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    String? date(dynamic seconds) => seconds == null ? null :
        DateTime.fromMillisecondsSinceEpoch((seconds as num).toInt() * 1000, isUtc: true).toIso8601String();
    final me = Map<String, dynamic>.from(state['me'] as Map);
    final serverTime = (state['serverTime'] as num).toInt();
    bool valid(Map<String, dynamic> o) => o['revoked'] != true &&
        (o['expiresAt'] == null || (o['expiresAt'] as num) > serverTime);
    final users = <String, Map<String, dynamic>>{};
    void addUser(Map<String, dynamic> u) {
      users[u['id'] as String] = {
        'id': u['id'], 'name': u['name'] ?? u['id'], 'avatar': u['avatar'] ?? '学',
        'isGuest': u['isGuest'] ?? false, 'profileComplete': u['profileComplete'] ?? false,
        'isMember': u['isMember'] ?? ((u['memberUntil'] as num? ?? 0) > serverTime),
        'friendIds': u['friendIds'] ?? [], 'activeFrameId': u['activeFrameId'],
      };
    }
    for (final u in list('users')) { addUser(u); }
    addUser(me);
    void known(dynamic id) {
      if (id is String && !users.containsKey(id)) addUser({'id': id, 'name': '用户 ${id.substring(0, id.length > 6 ? 6 : id.length)}'});
    }
    holdings = list('holdings');
    _serverNow = DateTime.fromMillisecondsSinceEpoch(serverTime * 1000);
    _receivedAt = DateTime.now();
    for (final h in holdings) { known(h['userId']); }
    final badges = list('badges').map((b) {
      known(b['issuerId']);
      final holders = holdings.where((h) => h['badgeId'] == b['id'] && valid(h)).map((h) => h['userId']).toList();
      for (final id in holders) { known(id); }
      return {...b, 'code': b['code'] ?? '', 'expiresAt': date(b['expiresAt']), 'recipientIds': holders};
    }).toList();
    final presence = list('presence');
    final residents = list('residents');
    final rooms = list('rooms').map((r) {
      known(r['ownerId']);
      for (final id in r['adminIds'] as List) { known(id); }
      final people = <String, Map<String, dynamic>>{};
      for (final x in residents.where((p) => p['roomId'] == r['id'])) {
        if (x['status'] == 'rejected') continue;
        known(x['userId']);
        people[x['userId']] = {'userId': x['userId'], 'approved': x['status'] == 'approved', 'isOnline': false, 'lastSeen': date(serverTime)};
      }
      // Owners are always residents; public visitors need not be permanent residents.
      people.putIfAbsent(r['ownerId'], () => {'userId': r['ownerId'], 'approved': true, 'isOnline': false, 'lastSeen': date(serverTime)});
      for (final p in presence.where((p) => p['roomId'] == r['id'])) {
        known(p['userId']);
        final x = people.putIfAbsent(p['userId'], () => {'userId': p['userId'], 'approved': false});
        x['isOnline'] = p['online']; x['lastSeen'] = date(p['lastSeen']);
      }
      return {'id': r['id'], 'name': r['name'], 'ownerId': r['ownerId'],
        'createdAt': date(r['createdAt']), 'isPrivate': r['private'], 'requiredBadgeId': r['badgeId'],
        'adminIds': r['adminIds'], 'residents': people.values.toList(),
        'backgroundId': r['background'], 'musicId': r['music'], 'emojiEnabled': r['emojiEnabled']};
    }).toList();
    final friends = list('friends').map((f) {
      known(f['fromId']); known(f['toId']);
      return {...f, 'status': f['status'] == 'rejected' ? 'declined' : f['status']};
    }).toList();
    final gifts = list('orders').map((o) {
      known(o['senderId']); known(o['recipientId']);
      return {...o, 'durationMs': (o['durationDays'] as num).toInt() * 86400000,
        'activatedAt': date(o['activatedAt']), 'expiresAt': date(o['expiresAt'])};
    }).toList();
    final events = list('events').map((e) {
      known(e['userId']); return {...e, 'createdAt': date(e['at'])};
    }).toList();
    for (final id in me['friendIds'] as List? ?? []) { known(id); }
    // importJson validates references atomically; overridden sweep never mutates server state.
    importJson(jsonEncode({'version': 1, 'serial': 0, 'currentUserId': me['id'],
      'users': users.values.toList(), 'badges': badges, 'rooms': rooms,
      'friendRequests': friends, 'gifts': gifts, 'emojiEvents': events}));
    resources = list('resources');
    role = me['role'] as String? ?? 'user';
  }

  @override
  Future<void> updateProfile({required String name, String avatar = '🙂'}) async { await command('profile', {'name': name, 'avatar': avatar}); }
  @override
  Future<StudyBadge> createBadge({required String name, Duration? validity}) async {
    final r = await command('badge.create', {'name': name, 'days': validity?.inDays, 'holdingDays': validity?.inDays});
    return badgeById(r['id']);
  }
  @override
  Future<StudyBadge> redeemBadge(String code) async {
    final previous = receivedBadges.map((b) => b.id).toSet();
    await command('badge.redeem', {'code': code.trim()});
    return receivedBadges.firstWhere((b) => !previous.contains(b.id));
  }
  @override
  Future<void> revokeBadge(String badgeId) async { await command('badge.revoke', {'badgeId': badgeId}); }
  @override
  Future<void> revokeBadgeRecipient(String badgeId, String userId) async { await command('holding.revoke', {'badgeId': badgeId, 'userId': userId}); }
  @override
  Future<void> renewBadge({required String badgeId, Duration? validity}) async { await command('badge.renew', {'badgeId': badgeId, 'days': validity?.inDays}); }
  @override
  Future<StudyRoom> createRoom({required String name, bool isPrivate = false, String? requiredBadgeId}) async {
    final r = await command('room.create', {'name': name, 'private': isPrivate, 'badgeId': requiredBadgeId});
    return roomById(r['id']);
  }
  @override
  Future<void> requestJoinRoom(String roomId) async { await command('room.apply', {'roomId': roomId}); }
  @override
  Future<void> approveResident({required String roomId, required String userId}) async { await command('room.review', {'roomId': roomId, 'userId': userId, 'status': 'approved'}); }
  @override
  Future<void> setResidentOnline({required String roomId, required bool online}) async {
    await command(online ? 'room.enter' : 'room.leave', {'roomId': roomId});
    _activeRoom = online ? roomId : null;
  }
  @override
  Future<void> addAdmin({required String roomId, required String userId}) => reorderAdmins(roomId: roomId, userIds: {...roomById(roomId).adminIds, userId}.toList());
  @override
  Future<void> removeAdmin({required String roomId, required String userId}) => reorderAdmins(roomId: roomId, userIds: roomById(roomId).adminIds.where((id) => id != userId).toList());
  @override
  Future<void> reorderAdmins({required String roomId, required List<String> userIds}) async { await command('room.admins', {'roomId': roomId, 'userIds': userIds}); }
  @override
  Future<void> updateRoomAmbience({required String roomId, String? backgroundId, String? musicId, bool? emojiEnabled}) async {
    await command('room.settings', {'roomId': roomId, if (backgroundId != null) 'background': backgroundId, if (musicId != null) 'music': musicId, if (emojiEnabled != null) 'emojiEnabled': emojiEnabled});
  }
  @override
  Future<EmojiEvent> sendEmoji({required String roomId, required String emoji}) async {
    await command('room.emoji', {'roomId': roomId, 'emoji': emoji});
    return emojiEvents.lastWhere((e) => e.roomId == roomId && e.userId == currentUser.id);
  }
  @override
  Future<FriendRequest> sendFriendRequest(String userId) async {
    await command('friend.request', {'userId': userId});
    return friendRequests.lastWhere((f) => f.fromId == currentUser.id && f.toId == userId);
  }
  @override
  Future<void> acceptFriendRequest(String requestId) async { await command('friend.review', {'id': requestId, 'status': 'accepted'}); }
  @override
  Future<void> declineFriendRequest(String requestId) async { await command('friend.review', {'id': requestId, 'status': 'rejected'}); }
  @override
  Future<FrameGift> purchaseGift({required String recipientId, required String frameId, required Duration duration}) async {
    final r = await command('order.create', {'recipientId': recipientId, 'frameId': frameId});
    return giftById(r['id']);
  }
  @override
  Future<void> acceptGift(String giftId) async { await command('order.accept', {'id': giftId}); }
  @override
  Future<void> switchFrame(String? giftId) async { await command('frame.switch', {'id': giftId}); }
  @override
  void dispose() { _disposed = true; _poll?.cancel(); _client.close(); super.dispose(); }
}
