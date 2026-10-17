import 'dart:convert';

import 'package:flutter/foundation.dart';

class StudyUser {
  StudyUser({
    required this.id,
    required this.name,
    this.isGuest = false,
    this.profileComplete = false,
    this.isMember = false,
    this.avatar = '🙂',
    this.activeFrameId,
    Set<String>? friendIds,
  }) : friendIds = friendIds ?? {};
  final String id;
  String name, avatar;
  bool isGuest, profileComplete, isMember;
  String? activeFrameId;
  final Set<String> friendIds;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'isGuest': isGuest,
    'profileComplete': profileComplete,
    'isMember': isMember,
    'activeFrameId': activeFrameId,
    'friendIds': friendIds.toList(),
  };
  factory StudyUser.fromJson(Map<String, dynamic> j) => StudyUser(
    id: j['id'],
    name: j['name'],
    avatar: j['avatar'],
    isGuest: j['isGuest'],
    profileComplete: j['profileComplete'],
    isMember: j['isMember'],
    activeFrameId: j['activeFrameId'],
    friendIds: Set<String>.from(j['friendIds']),
  );
}

class StudyBadge {
  StudyBadge({
    required this.id,
    required this.name,
    required this.code,
    required this.issuerId,
    this.expiresAt,
    this.revoked = false,
    Set<String>? recipientIds,
  }) : recipientIds = recipientIds ?? {};
  final String id, issuerId;
  String name, code;
  DateTime? expiresAt;
  bool revoked;
  final Set<String> recipientIds;
  bool get isLifetime => expiresAt == null;
  bool isValidAt(DateTime now) =>
      !revoked && (expiresAt == null || now.isBefore(expiresAt!));
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'issuerId': issuerId,
    'expiresAt': expiresAt?.toIso8601String(),
    'revoked': revoked,
    'recipientIds': recipientIds.toList(),
  };
  factory StudyBadge.fromJson(Map<String, dynamic> j) => StudyBadge(
    id: j['id'],
    name: j['name'],
    code: j['code'],
    issuerId: j['issuerId'],
    expiresAt: _date(j['expiresAt']),
    revoked: j['revoked'],
    recipientIds: Set<String>.from(j['recipientIds']),
  );
}

class RoomResident {
  RoomResident({
    required this.userId,
    required this.lastSeen,
    this.approved = false,
    this.isOnline = false,
  });
  final String userId;
  bool approved, isOnline;
  DateTime lastSeen;
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'approved': approved,
    'isOnline': isOnline,
    'lastSeen': lastSeen.toIso8601String(),
  };
  factory RoomResident.fromJson(Map<String, dynamic> j) => RoomResident(
    userId: j['userId'],
    approved: j['approved'],
    isOnline: j['isOnline'],
    lastSeen: DateTime.parse(j['lastSeen']),
  );
}

class StudyRoom {
  StudyRoom({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    this.isPrivate = false,
    this.requiredBadgeId,
    List<String>? adminIds,
    List<RoomResident>? residents,
    this.backgroundId = 'library',
    this.musicId = 'rain',
    this.emojiEnabled = true,
  }) : adminIds = adminIds ?? [],
       residents = residents ?? [];
  final String id;
  String name, ownerId, backgroundId, musicId;
  final bool isPrivate;
  final String? requiredBadgeId;
  final DateTime createdAt;
  bool emojiEnabled;
  final List<String> adminIds;
  final List<RoomResident> residents;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
    'isPrivate': isPrivate,
    'requiredBadgeId': requiredBadgeId,
    'adminIds': adminIds,
    'residents': residents.map((e) => e.toJson()).toList(),
    'backgroundId': backgroundId,
    'musicId': musicId,
    'emojiEnabled': emojiEnabled,
  };
  factory StudyRoom.fromJson(Map<String, dynamic> j) => StudyRoom(
    id: j['id'],
    name: j['name'],
    ownerId: j['ownerId'],
    createdAt: DateTime.parse(j['createdAt']),
    isPrivate: j['isPrivate'],
    requiredBadgeId: j['requiredBadgeId'],
    adminIds: List<String>.from(j['adminIds']),
    residents: (j['residents'] as List)
        .map((e) => RoomResident.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    backgroundId: j['backgroundId'],
    musicId: j['musicId'],
    emojiEnabled: j['emojiEnabled'],
  );
}

class FriendRequest {
  FriendRequest({
    required this.id,
    required this.fromId,
    required this.toId,
    this.status = 'pending',
  });
  final String id, fromId, toId;
  String status;
  Map<String, dynamic> toJson() => {
    'id': id,
    'fromId': fromId,
    'toId': toId,
    'status': status,
  };
  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
    id: j['id'],
    fromId: j['fromId'],
    toId: j['toId'],
    status: j['status'],
  );
}

class FrameGift {
  FrameGift({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.frameId,
    required this.duration,
    this.status = 'paid',
    this.activatedAt,
    this.expiresAt,
  });
  final String id, senderId, recipientId, frameId;
  final Duration duration;
  String status;
  DateTime? activatedAt, expiresAt;
  bool isActiveAt(DateTime now) =>
      status == 'active' && expiresAt != null && now.isBefore(expiresAt!);
  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'recipientId': recipientId,
    'frameId': frameId,
    'durationMs': duration.inMilliseconds,
    'status': status,
    'activatedAt': activatedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
  };
  factory FrameGift.fromJson(Map<String, dynamic> j) => FrameGift(
    id: j['id'],
    senderId: j['senderId'],
    recipientId: j['recipientId'],
    frameId: j['frameId'],
    duration: Duration(milliseconds: j['durationMs']),
    status: j['status'],
    activatedAt: _date(j['activatedAt']),
    expiresAt: _date(j['expiresAt']),
  );
}

class EmojiEvent {
  EmojiEvent({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });
  final String id, roomId, userId, emoji;
  final DateTime createdAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'roomId': roomId,
    'userId': userId,
    'emoji': emoji,
    'createdAt': createdAt.toIso8601String(),
  };
  factory EmojiEvent.fromJson(Map<String, dynamic> j) => EmojiEvent(
    id: j['id'],
    roomId: j['roomId'],
    userId: j['userId'],
    emoji: j['emoji'],
    createdAt: DateTime.parse(j['createdAt']),
  );
}

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);

/// In-memory demo domain. Call sweep on app resume or a periodic UI timer.
/// JSON snapshots can be persisted by the application without external services.
class StudyStore extends ChangeNotifier {
  StudyStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _users.add(StudyUser(id: 'guest', name: '访客', isGuest: true));
  }
  factory StudyStore.demo({DateTime Function()? clock}) {
    final s = StudyStore(clock: clock);
    s._users.addAll([
      StudyUser(
        id: 'lin',
        name: '林同学',
        profileComplete: true,
        isMember: true,
        avatar: '🌱',
      ),
      StudyUser(id: 'chen', name: '陈同学', profileComplete: true, avatar: '🐱'),
      StudyUser(
        id: 'zhou',
        name: '周同学',
        profileComplete: true,
        isMember: true,
        avatar: '🦊',
      ),
      StudyUser(id: 'new', name: '新同学'),
    ]);
    s._currentUserId = 'lin';
    final badge = s.createBadge(
      name: '晨光自习社',
      validity: const Duration(days: 30),
    );
    badge.recipientIds.addAll(['chen', 'zhou']);
    final room = s.createRoom(name: '晨光图书馆', requiredBadgeId: badge.id);
    room.adminIds.addAll(['chen', 'zhou']);
    room.residents.addAll([
      RoomResident(
        userId: 'chen',
        approved: true,
        isOnline: true,
        lastSeen: s.now,
      ),
      RoomResident(
        userId: 'zhou',
        approved: true,
        lastSeen: s.now.subtract(const Duration(hours: 2)),
      ),
    ]);
    s.createRoom(name: '考研冲刺小屋', isPrivate: true);
    s._currentUserId = 'chen';
    s.createRoom(name: '一起专注 25 分钟');
    s.sendFriendRequest('lin');
    s.purchaseGift(
      recipientId: 'lin',
      frameId: 'starlight',
      duration: const Duration(days: 7),
    );
    s._currentUserId = 'lin';
    return s;
  }

  final DateTime Function() _clock;
  DateTime get now => _clock();
  int _serial = 0;
  String _currentUserId = 'guest';
  final List<StudyUser> _users = [];
  final List<StudyRoom> _rooms = [];
  final List<StudyBadge> _badges = [];
  final List<FriendRequest> _friendRequests = [];
  final List<FrameGift> _gifts = [];
  final List<EmojiEvent> _emojiEvents = [];
  static const Map<String, String> backgrounds = {
    'library': '静谧图书馆',
    'forest': '林间晨光',
    'night': '城市夜读',
    'sea': '海边书桌',
  };
  static const Map<String, String> musicTracks = {
    'rain': '雨声',
    'piano': '轻钢琴',
    'forest': '森林白噪音',
    'silent': '静音',
  };
  static const Map<String, String> frameCatalog = {
    'starlight': '星光环绕',
    'blossom': '樱花信笺',
    'laurel': '桂冠荣耀',
  };
  List<StudyUser> get users => List.unmodifiable(_users);
  StudyUser get currentUser => userById(_currentUserId);
  List<StudyRoom> get rooms => List.unmodifiable(_rooms);
  List<StudyBadge> get badges => List.unmodifiable(_badges);
  List<FriendRequest> get friendRequests => List.unmodifiable(_friendRequests);
  List<FrameGift> get gifts => List.unmodifiable(_gifts);
  List<EmojiEvent> get emojiEvents => List.unmodifiable(_emojiEvents);
  List<StudyBadge> get issuedBadges =>
      _badges.where((b) => b.issuerId == currentUser.id).toList();
  List<StudyBadge> get receivedBadges =>
      _badges.where((b) => b.recipientIds.contains(currentUser.id)).toList();
  List<FrameGift> get activeFrames => _gifts
      .where((g) => g.recipientId == currentUser.id && g.isActiveAt(now))
      .toList();
  StudyUser userById(String id) => _users.firstWhere(
    (u) => u.id == id,
    orElse: () => throw StateError('用户不存在'),
  );
  StudyRoom roomById(String id) => _rooms.firstWhere(
    (r) => r.id == id,
    orElse: () => throw StateError('房间不存在'),
  );
  StudyBadge badgeById(String id) => _badges.firstWhere(
    (b) => b.id == id,
    orElse: () => throw StateError('徽章不存在'),
  );
  FrameGift giftById(String id) => _gifts.firstWhere(
    (g) => g.id == id,
    orElse: () => throw StateError('礼物不存在'),
  );
  String _id(String prefix) => '$prefix-${++_serial}';
  void _require(bool value, String message) {
    if (!value) throw StateError(message);
  }

  void _registered() => _require(!currentUser.isGuest, '请先注册');
  void _complete() {
    _registered();
    _require(currentUser.profileComplete, '请先完善个人资料');
  }

  String _name(String value) {
    _require(value.trim().isNotEmpty, '名称不能为空');
    return value.trim();
  }

  bool ownsBadge(String userId, String badgeId) {
    final b = badgeById(badgeId);
    return b.isValidAt(now) && b.recipientIds.contains(userId);
  }

  bool canOwnRoom(String userId, StudyRoom room) {
    final u = userById(userId);
    return !u.isGuest &&
        u.profileComplete &&
        (room.requiredBadgeId == null ||
            ownsBadge(userId, room.requiredBadgeId!));
  }

  bool canManageRoom(StudyRoom room) =>
      room.ownerId == currentUser.id || room.adminIds.contains(currentUser.id);
  RoomResident? residentOf(StudyRoom room, String userId) {
    for (final r in room.residents) {
      if (r.userId == userId) return r;
    }
    return null;
  }

  void switchUser(String userId) {
    userById(userId);
    _currentUserId = userId;
    sweep();
    notifyListeners();
  }

  StudyUser registerGuest({required String name}) {
    _require(currentUser.isGuest, '当前用户已注册');
    currentUser.name = _name(name);
    currentUser.isGuest = false;
    notifyListeners();
    return currentUser;
  }

  void updateProfile({required String name, String avatar = '🙂'}) {
    _registered();
    currentUser.name = _name(name);
    currentUser.avatar = _name(avatar);
    currentUser.profileComplete = true;
    notifyListeners();
  }

  StudyBadge createBadge({required String name, Duration? validity}) {
    _complete();
    _duration(validity);
    final id = _id('badge');
    final b = StudyBadge(
      id: id,
      name: _name(name),
      code: 'STUDY-${_id('code').toUpperCase()}',
      issuerId: currentUser.id,
      expiresAt: validity == null ? null : now.add(validity),
      recipientIds: {currentUser.id},
    );
    _badges.add(b);
    notifyListeners();
    return b;
  }

  void _duration(Duration? d) =>
      _require(d == null || d > Duration.zero, '有效期必须大于零');
  StudyBadge redeemBadge(String code) {
    _registered();
    final b = _badges.firstWhere(
      (b) => b.code == code.trim().toUpperCase(),
      orElse: () => throw StateError('兑换码无效'),
    );
    _require(b.isValidAt(now), '徽章已失效');
    b.recipientIds.add(currentUser.id);
    notifyListeners();
    return b;
  }

  void revokeBadge(String badgeId) {
    final b = badgeById(badgeId);
    _require(b.issuerId == currentUser.id, '仅发行者可撤销');
    b.revoked = true;
    sweep();
    notifyListeners();
  }

  /// Revoke one recipient while keeping the badge and other holders valid.
  /// Room succession and presence are updated immediately, including when the
  /// issuer removes their own badge ownership.
  void revokeBadgeRecipient(String badgeId, String userId) {
    final b = badgeById(badgeId);
    _require(b.issuerId == currentUser.id, '仅发行者可收回徽章');
    userById(userId);
    b.recipientIds.remove(userId);
    sweep();
    notifyListeners();
  }

  /// Named-argument alias retained for existing callers.
  void revokeBadgeFromUser({required String badgeId, required String userId}) =>
      revokeBadgeRecipient(badgeId, userId);
  void renewBadge({required String badgeId, Duration? validity}) {
    final b = badgeById(badgeId);
    _require(b.issuerId == currentUser.id, '仅发行者可续期');
    _require(!b.revoked, '已撤销徽章不可续期');
    _duration(validity);
    final base = b.expiresAt != null && b.expiresAt!.isAfter(now)
        ? b.expiresAt!
        : now;
    b.expiresAt = validity == null ? null : base.add(validity);
    notifyListeners();
  }

  StudyRoom createRoom({
    required String name,
    bool isPrivate = false,
    String? requiredBadgeId,
  }) {
    _complete();
    if (requiredBadgeId != null) {
      _require(ownsBadge(currentUser.id, requiredBadgeId), '需持有有效徽章');
    }
    final r = StudyRoom(
      id: _id('room'),
      name: _name(name),
      ownerId: currentUser.id,
      createdAt: now,
      isPrivate: isPrivate,
      requiredBadgeId: requiredBadgeId,
      residents: [
        RoomResident(
          userId: currentUser.id,
          approved: true,
          isOnline: true,
          lastSeen: now,
        ),
      ],
    );
    _rooms.add(r);
    notifyListeners();
    return r;
  }

  void requestJoinRoom(String roomId) {
    sweep();
    final room = roomById(roomId);
    _require(
      room.requiredBadgeId == null ||
          ownsBadge(currentUser.id, room.requiredBadgeId!),
      '需持有有效徽章',
    );
    var r = residentOf(room, currentUser.id);
    if (r == null) {
      r = RoomResident(userId: currentUser.id, lastSeen: now);
      room.residents.add(r);
    }
    r.isOnline = r.approved;
    r.lastSeen = now;
    notifyListeners();
  }

  void approveResident({required String roomId, required String userId}) {
    sweep();
    final room = roomById(roomId);
    _require(room.ownerId == currentUser.id, '仅房主可批准入驻');
    final r = residentOf(room, userId);
    _require(r != null, '没有入驻申请');
    _require(
      room.requiredBadgeId == null || ownsBadge(userId, room.requiredBadgeId!),
      '申请者徽章已失效',
    );
    r!.approved = true;
    notifyListeners();
  }

  /// Leaving preserves approved residency; it only changes presence.
  void leaveRoom(String roomId) =>
      setResidentOnline(roomId: roomId, online: false);
  void setResidentOnline({required String roomId, required bool online}) {
    if (online) sweep();
    final room = roomById(roomId);
    final r = residentOf(room, currentUser.id);
    _require(r != null && r.approved, '请先申请入驻');
    _require(
      !online ||
          room.requiredBadgeId == null ||
          ownsBadge(currentUser.id, room.requiredBadgeId!),
      '需持有有效徽章',
    );
    r!.isOnline = online;
    r.lastSeen = now;
    notifyListeners();
  }

  void addAdmin({required String roomId, required String userId}) {
    sweep();
    final r = roomById(roomId);
    _require(r.ownerId == currentUser.id, '仅房主可设置管理员');
    _require(
      userId != r.ownerId &&
          canOwnRoom(userId, r) &&
          residentOf(r, userId)?.approved == true,
      '管理员须为符合资格的已入驻用户',
    );
    if (!r.adminIds.contains(userId)) r.adminIds.add(userId);
    notifyListeners();
  }

  void removeAdmin({required String roomId, required String userId}) {
    final r = roomById(roomId);
    _require(r.ownerId == currentUser.id, '仅房主可设置管理员');
    r.adminIds.remove(userId);
    notifyListeners();
  }

  void reorderAdmins({required String roomId, required List<String> userIds}) {
    final r = roomById(roomId);
    _require(r.ownerId == currentUser.id, '仅房主可排序');
    _require(
      userIds.length == r.adminIds.length &&
          userIds.toSet().length == userIds.length &&
          userIds.every(r.adminIds.contains),
      '管理员列表不匹配',
    );
    r.adminIds
      ..clear()
      ..addAll(userIds);
    notifyListeners();
  }

  void updateRoomAmbience({
    required String roomId,
    String? backgroundId,
    String? musicId,
    bool? emojiEnabled,
  }) {
    sweep();
    final r = roomById(roomId);
    _require(canManageRoom(r), '需要管理员权限');
    _require(
      backgroundId == null || backgrounds.containsKey(backgroundId),
      '背景不存在',
    );
    _require(musicId == null || musicTracks.containsKey(musicId), '音乐不存在');
    if (backgroundId != null) r.backgroundId = backgroundId;
    if (musicId != null) r.musicId = musicId;
    if (emojiEnabled != null) r.emojiEnabled = emojiEnabled;
    notifyListeners();
  }

  EmojiEvent sendEmoji({required String roomId, required String emoji}) {
    sweep();
    final r = roomById(roomId);
    final resident = residentOf(r, currentUser.id);
    _require(
      r.emojiEnabled &&
          resident?.approved == true &&
          resident?.isOnline == true,
      '当前不能发送表情',
    );
    _require(emoji.trim().isNotEmpty && emoji.runes.length <= 16, '表情无效');
    final e = EmojiEvent(
      id: _id('emoji'),
      roomId: roomId,
      userId: currentUser.id,
      emoji: emoji,
      createdAt: now,
    );
    _emojiEvents.add(e);
    if (_emojiEvents.length > 200) _emojiEvents.removeAt(0);
    notifyListeners();
    return e;
  }

  FriendRequest sendFriendRequest(String userId) {
    _registered();
    final target = userById(userId);
    _require(!target.isGuest && userId != currentUser.id, '请选择其他注册用户');
    _require(!currentUser.friendIds.contains(userId), '已经是好友');
    _require(
      !_friendRequests.any(
        (r) =>
            r.status == 'pending' &&
            ((r.fromId == currentUser.id && r.toId == userId) ||
                (r.toId == currentUser.id && r.fromId == userId)),
      ),
      '已有待处理申请',
    );
    final r = FriendRequest(
      id: _id('friend'),
      fromId: currentUser.id,
      toId: userId,
    );
    _friendRequests.add(r);
    notifyListeners();
    return r;
  }

  void acceptFriendRequest(String requestId) => _answerFriend(requestId, true);
  void declineFriendRequest(String requestId) =>
      _answerFriend(requestId, false);
  void _answerFriend(String id, bool accept) {
    final r = _friendRequests.firstWhere(
      (r) => r.id == id,
      orElse: () => throw StateError('申请不存在'),
    );
    _require(r.toId == currentUser.id && r.status == 'pending', '无法处理此申请');
    r.status = accept ? 'accepted' : 'declined';
    if (accept) {
      currentUser.friendIds.add(r.fromId);
      userById(r.fromId).friendIds.add(r.toId);
    }
    notifyListeners();
  }

  /// Local mock checkout succeeds immediately. Paid gifts start only on acceptance.
  FrameGift purchaseGift({
    required String recipientId,
    required String frameId,
    required Duration duration,
  }) {
    _registered();
    final recipient = userById(recipientId);
    _require(!recipient.isGuest && recipientId != currentUser.id, '请选择其他注册用户');
    _require(frameCatalog.containsKey(frameId), '头像框不存在');
    _duration(duration);
    final g = FrameGift(
      id: _id('gift'),
      senderId: currentUser.id,
      recipientId: recipientId,
      frameId: frameId,
      duration: duration,
    );
    _gifts.add(g);
    notifyListeners();
    return g;
  }

  void acceptGift(String giftId) {
    final g = giftById(giftId);
    _require(g.recipientId == currentUser.id && g.status == 'paid', '礼物不可领取');
    g.status = 'active';
    g.activatedAt = now;
    g.expiresAt = now.add(g.duration);
    currentUser.activeFrameId = g.frameId;
    notifyListeners();
  }

  /// Pass an accepted gift ID, or null to remove the equipped frame.
  void switchFrame(String? giftId) {
    sweep();
    if (giftId == null) {
      currentUser.activeFrameId = null;
    } else {
      final g = giftById(giftId);
      _require(
        g.recipientId == currentUser.id && g.isActiveAt(now),
        '头像框未激活或已到期',
      );
      currentUser.activeFrameId = g.frameId;
    }
    notifyListeners();
  }

  /// Expiry keeps resident history, but disconnects ineligible users. Succession
  /// follows explicit admin order and does not depend on online presence.
  void sweep() {
    var changed = false;
    for (final g in _gifts) {
      if (g.status == 'active' && !g.isActiveAt(now)) {
        g.status = 'expired';
        changed = true;
      }
    }
    for (final u in _users) {
      if (u.activeFrameId != null &&
          !_gifts.any(
            (g) =>
                g.recipientId == u.id &&
                g.frameId == u.activeFrameId &&
                g.isActiveAt(now),
          )) {
        u.activeFrameId = null;
        changed = true;
      }
    }
    for (final room in List<StudyRoom>.from(_rooms)) {
      if (!canOwnRoom(room.ownerId, room)) {
        final eligible = room.adminIds
            .where(
              (id) =>
                  canOwnRoom(id, room) &&
                  residentOf(room, id)?.approved == true,
            )
            .toList();
        if (eligible.isEmpty) {
          _rooms.remove(room);
          _emojiEvents.removeWhere((e) => e.roomId == room.id);
          changed = true;
          continue;
        }
        room.ownerId = eligible.first;
        room.adminIds.remove(eligible.first);
        changed = true;
      }
      final invalid = room.adminIds
          .where((id) => !canOwnRoom(id, room))
          .toList();
      if (invalid.isNotEmpty) {
        room.adminIds.removeWhere(invalid.contains);
        changed = true;
      }
      if (room.requiredBadgeId != null) {
        for (final r in room.residents) {
          if (r.isOnline && !ownsBadge(r.userId, room.requiredBadgeId!)) {
            r.isOnline = false;
            r.lastSeen = now;
            changed = true;
          }
        }
      }
    }
    if (changed) notifyListeners();
  }

  String exportJson() => jsonEncode({
    'version': 1,
    'serial': _serial,
    'currentUserId': _currentUserId,
    'users': _users.map((e) => e.toJson()).toList(),
    'rooms': _rooms.map((e) => e.toJson()).toList(),
    'badges': _badges.map((e) => e.toJson()).toList(),
    'friendRequests': _friendRequests.map((e) => e.toJson()).toList(),
    'gifts': _gifts.map((e) => e.toJson()).toList(),
    'emojiEvents': _emojiEvents.map((e) => e.toJson()).toList(),
  });

  /// Parses into a temporary store so invalid snapshots never partially apply.
  void importJson(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    _require(j['version'] == 1, '不支持的存档版本');
    final temp = StudyStore(clock: _clock);
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) make) =>
        (j[key] as List)
            .map((e) => make(Map<String, dynamic>.from(e)))
            .toList();
    temp._users
      ..clear()
      ..addAll(parse('users', StudyUser.fromJson));
    temp._badges.addAll(parse('badges', StudyBadge.fromJson));
    temp._rooms.addAll(parse('rooms', StudyRoom.fromJson));
    temp._friendRequests.addAll(
      parse('friendRequests', FriendRequest.fromJson),
    );
    temp._gifts.addAll(parse('gifts', FrameGift.fromJson));
    temp._emojiEvents.addAll(parse('emojiEvents', EmojiEvent.fromJson));
    temp._currentUserId = j['currentUserId'] as String;
    temp._serial = j['serial'] as int;
    temp._validateSnapshot();
    _users
      ..clear()
      ..addAll(temp._users);
    _badges
      ..clear()
      ..addAll(temp._badges);
    _rooms
      ..clear()
      ..addAll(temp._rooms);
    _friendRequests
      ..clear()
      ..addAll(temp._friendRequests);
    _gifts
      ..clear()
      ..addAll(temp._gifts);
    _emojiEvents
      ..clear()
      ..addAll(temp._emojiEvents);
    _currentUserId = temp._currentUserId;
    _serial = temp._serial;
    sweep();
    notifyListeners();
  }

  void _validateSnapshot() {
    _require(_serial >= 0 && _users.isNotEmpty, '无效存档');
    void unique(Iterable<String> ids) =>
        _require(ids.length == ids.toSet().length, '存档标识重复');
    unique(_users.map((u) => u.id));
    unique(_rooms.map((r) => r.id));
    unique(_badges.map((b) => b.id));
    unique(_badges.map((b) => b.code));
    unique(_gifts.map((g) => g.id));
    unique(_friendRequests.map((r) => r.id));
    unique(_emojiEvents.map((e) => e.id));
    userById(_currentUserId);
    for (final u in _users) {
      for (final id in u.friendIds) {
        userById(id);
      }
    }
    for (final b in _badges) {
      userById(b.issuerId);
      for (final id in b.recipientIds) {
        userById(id);
      }
    }
    for (final r in _rooms) {
      userById(r.ownerId);
      if (r.requiredBadgeId != null) badgeById(r.requiredBadgeId!);
      unique(r.adminIds);
      unique(r.residents.map((e) => e.userId));
      _require(
        backgrounds.containsKey(r.backgroundId) &&
            musicTracks.containsKey(r.musicId),
        '无效房间配置',
      );
      for (final id in r.adminIds) {
        userById(id);
      }
      for (final resident in r.residents) {
        userById(resident.userId);
      }
    }
    for (final g in _gifts) {
      userById(g.senderId);
      userById(g.recipientId);
      _duration(g.duration);
      _require(
        frameCatalog.containsKey(g.frameId) &&
            ['paid', 'active', 'expired'].contains(g.status),
        '无效礼物',
      );
      _require(
        g.status == 'paid' || (g.activatedAt != null && g.expiresAt != null),
        '无效礼物日期',
      );
    }
    for (final r in _friendRequests) {
      userById(r.fromId);
      userById(r.toId);
      _require(
        ['pending', 'accepted', 'declined'].contains(r.status),
        '无效好友申请',
      );
    }
    for (final e in _emojiEvents) {
      userById(e.userId);
      roomById(e.roomId);
    }
  }
}
