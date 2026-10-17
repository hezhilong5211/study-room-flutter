import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'remote_store.dart';

import 'domain.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = RemoteStudyStore(baseUrl: const String.fromEnvironment(
    'STUDY_API_URL', defaultValue: 'http://localhost:8080'));
  runApp(StudyApp(store: store));
  unawaited(store.connect());
}

const ink = Color(0xff2e3a52);
const paper = Color(0xfff3ecdf);
const blue = Color(0xff3550b0);
const gold = Color(0xffe9cf95);

class StudyApp extends StatelessWidget {
  const StudyApp({super.key, required this.store});
  final StudyStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '一起自习 · 四季',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, surface: paper),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        centerTitle: false,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .65),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xfff2c779),
          foregroundColor: const Color(0xff4d351f),
          elevation: 3,
          shadowColor: const Color(0xffa8742a),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      cardTheme: const CardThemeData(color: Color(0xffefe6d6), elevation: 0),
    ),
    home: StudyHome(store: store),
  );
}

class StudyHome extends StatefulWidget {
  const StudyHome({super.key, required this.store});
  final StudyStore store;
  @override
  State<StudyHome> createState() => _StudyHomeState();
}

class _StudyHomeState extends State<StudyHome> {
  StudyStore get s => widget.store;
  int tab = 0;
  String? selected;
  Timer? clock;
  int seconds = 0;
  bool focusing = false;
  bool immersive = false;
  bool memberWall = false;
  final roomSearch = TextEditingController();
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      s.sweep();
      if (mounted && focusing) setState(() => seconds++);
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    roomSearch.dispose();
    super.dispose();
  }

  Future<void> act(FutureOr<dynamic> Function() action) async {
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is StateError ? e.message : '$e')),
      );
    }
  }

  Future<void> exitRoom() async {
    final room = s.rooms.where((r) => r.id == selected).firstOrNull;
    final resident = room?.residents
        .where((p) => p.userId == s.currentUser.id)
        .firstOrNull;
    if (resident?.isOnline == true) {
      await s.setResidentOnline(roomId: room!.id, online: false);
    }
    selected = null;
    focusing = false;
    seconds = 0;
  }

  String badgeStatus(StudyBadge badge) {
    if (badge.revoked) return '已撤销';
    if (!badge.isValidAt(s.now)) return '已过期';
    return badge.isLifetime
        ? '终身有效'
        : '有效期至 ${badge.expiresAt!.toLocal().toString().split('.').first}';
  }

  String holdingStatus(StudyBadge badge, String userId) {
    if (s is! RemoteStudyStore) return badgeStatus(badge);
    final h = (s as RemoteStudyStore).holding(badge.id, userId);
    if (h == null) return '未持有';
    if (h['revoked'] == true) return '个人持有已撤销';
    final end = h['expiresAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((h['expiresAt'] as num).toInt() * 1000);
    final personal = end == null ? '个人持有永久有效' : '${end.isAfter(s.now) ? "个人有效期至" : "个人持有已到期"} ${end.toLocal().toString().split(".").first}';
    return '$personal · 勋章${badgeStatus(badge)}';
  }

  String giftStatus(FrameGift gift) => switch (gift.status) {
    'pending' => '待支付（支付尚未配置）',
    'cancelled' => '已取消',
    'paid' => '待接受',
    'active' => gift.isActiveAt(s.now) ? '使用中' : '已过期',
    'expired' => '已过期',
    _ => '暂不可用',
  };

  StudyUser user(String id) => s.users.firstWhere((u) => u.id == id);
  void notice(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
  Future<void> sheet(
    String title,
    List<Widget> Function(BuildContext, StateSetter) content,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (ctx) => AnimatedBuilder(
      animation: s,
      builder: (ctx, _) => StatefulBuilder(
        builder: (ctx, refresh) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Container(
            key: const ValueKey('paper-sheet'),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .88,
            ),
            decoration: BoxDecoration(
              color: paper,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              border: Border.all(color: gold, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 24),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff435d9c), Color(0xff2e4378)],
                      ),
                      border: Border(bottom: BorderSide(color: gold, width: 2)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: paper,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, size: 18),
                          style: IconButton.styleFrom(
                            foregroundColor: paper,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: content(ctx, refresh),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget heading(String title, [String? subtitle]) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: Color(0xff747b88))),
        ],
      ],
    ),
  );
  Widget tag(String label, {Color color = blue}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 12)),
  );
  Widget avatar(StudyUser u, {double radius = 22}) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: switch (u.activeFrameId) {
          'starlight' => const Color(0xff7772c4),
          'blossom' => const Color(0xffcb7d99),
          'laurel' => const Color(0xffb98a40),
          _ => Colors.transparent,
        },
        width: u.activeFrameId == 'laurel' ? 4 : 2,
      ),
      boxShadow: u.activeFrameId == 'starlight'
          ? [
              BoxShadow(
                color: const Color(0xff7772c4).withValues(alpha: .35),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ]
          : null,
      gradient: u.activeFrameId == 'blossom'
          ? const LinearGradient(colors: [Color(0xffffdbe7), Color(0xfff5b6cb)])
          : null,
    ),
    child: CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xffe4dac5),
      child: Text(u.avatar, style: TextStyle(fontSize: radius)),
    ),
  );

  Future<void> enterRoom(StudyRoom r) => act(() async {
    if (selected != null && selected != r.id) await exitRoom();
    final me = s.residentOf(r, s.currentUser.id);
    if (me?.approved == true) await s.setResidentOnline(roomId: r.id, online: true);
    selected = r.id;
    immersive = false;
    memberWall = false;
    focusing = false;
    seconds = 0;
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: s,
    builder: (context, _) {
      final room = s.rooms.where((r) => r.id == selected).firstOrNull;
      return Scaffold(
        backgroundColor: const Color(0xff101626),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: room != null
                ? roomView(room)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xff26304d),
                          Color(0xff1c2338),
                          Color(0xff181e30),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          if (s is RemoteStudyStore && (!(s as RemoteStudyStore).ready || (s as RemoteStudyStore).error != null))
                            MaterialBanner(
                              content: Text((s as RemoteStudyStore).error ?? '正在连接自习室服务…'),
                              actions: [TextButton(onPressed: () => (s as RemoteStudyStore).connect(), child: const Text('重试'))],
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            child: Row(
                              children: [
                                Text(
                                  ['一起自习', '发现', '我的'][tab],
                                  style: const TextStyle(
                                    color: paper,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                                if (tab == 0)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Text(
                                      '四季',
                                      style: TextStyle(
                                        color: gold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                IconButton(
                                  tooltip: '账号登录与注册',
                                  onPressed: switchIdentity,
                                  icon: const Icon(
                                    Icons.switch_account_outlined,
                                    size: 20,
                                    color: gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: DefaultTextStyle(
                              style: const TextStyle(
                                color: paper,
                                fontSize: 13,
                              ),
                              child: tab == 0
                                  ? lobby()
                                  : tab == 1
                                  ? discover()
                                  : profile(),
                            ),
                          ),
                          Container(
                            height: 60,
                            decoration: const BoxDecoration(
                              color: Color(0xff0e121e),
                              border: Border(
                                top: BorderSide(color: Color(0xff34394a)),
                              ),
                            ),
                            child: Row(
                              children: [
                                for (var i = 0; i < 3; i++)
                                  Expanded(
                                    child: InkWell(
                                      key: ValueKey('nav-$i'),
                                      onTap: () => setState(() => tab = i),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            [
                                              Icons.door_front_door_outlined,
                                              Icons.explore_outlined,
                                              Icons.person_outline,
                                            ][i],
                                            size: 21,
                                            color: tab == i
                                                ? gold
                                                : const Color(0xff8d95a6),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            ['房间', '发现', '我的'][i],
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: tab == i
                                                  ? gold
                                                  : const Color(0xff8d95a6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      );
    },
  );

  Widget section(String title, [String? note]) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 8),
    child: Row(
      children: [
        Text(title, style: const TextStyle(color: gold, fontSize: 12)),
        if (note != null) ...[
          const Spacer(),
          Text(
            note,
            style: const TextStyle(color: Color(0xff9aa3b5), fontSize: 10),
          ),
        ],
      ],
    ),
  );
  BoxDecoration get nightCard => BoxDecoration(
    color: Colors.white.withValues(alpha: .06),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: paper.withValues(alpha: .12)),
  );
  int online(StudyRoom r) =>
      r.residents.where((p) => p.approved && p.isOnline).length;
  Widget lobby() => ListView(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
    children: [
      section('我加入的房间'),
      ...s.rooms
          .where(
            (r) =>
                r.ownerId == s.currentUser.id ||
                s.residentOf(r, s.currentUser.id)?.approved == true,
          )
          .map(roomCard),
      if (!s.rooms.any(
        (r) => s.residentOf(r, s.currentUser.id)?.approved == true,
      ))
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('还没有常驻房间，去发现页找一盏灯。'),
        ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: GoldButton(
              label: '创建房间',
              icon: Icons.add,
              onPressed: createRoom,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GoldButton(
              label: '凭编号进房',
              icon: Icons.key_outlined,
              onPressed: joinPrivate,
            ),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          '私密房间不在公开列表展示；凭完整房间编号申请常驻。',
          style: TextStyle(color: Color(0xff9aa3b5), fontSize: 11, height: 1.7),
        ),
      ),
    ],
  );
  Widget roomCard(StudyRoom r) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      key: ValueKey('room-${r.id}'),
      onTap: () => enterRoom(r),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: nightCard,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 76,
                height: 52,
                child: SeasonalWindow(season: r.backgroundId),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r.name}${r.isPrivate ? ' · 私密' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: paper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '此刻 ${online(r)} 人在 · ${r.residents.where((p) => p.approved).length} 位常驻',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff9aa3b5),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '房间号 ${r.id} · ${r.ownerId == s.currentUser.id
                        ? '我是房主'
                        : r.adminIds.contains(s.currentUser.id)
                        ? '我是管理员'
                        : '常驻成员'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xff9aa3b5),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: gold, size: 18),
          ],
        ),
      ),
    ),
  );

  Widget roundAction(String label, IconData icon, VoidCallback action) =>
      SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          tooltip: label,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xaa0a0e1a),
            foregroundColor: paper,
          ),
          onPressed: action,
          icon: Icon(icon, size: 19),
        ),
      );
  Widget member(StudyRoom r, RoomResident p, {bool large = false}) {
    final u = user(p.userId);
    final role = u.id == r.ownerId
        ? '房主'
        : r.adminIds.contains(u.id)
        ? '管理员'
        : null;
    return InkWell(
      onTap: () => personActions(u),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: p.isOnline ? gold : Colors.blueGrey,
                width: 2,
              ),
              boxShadow: p.isOnline
                  ? [
                      BoxShadow(
                        color: gold.withValues(alpha: .35),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Opacity(
              opacity: p.isOnline ? 1 : .5,
              child: avatar(u, radius: large ? 25 : 19),
            ),
          ),
          if (role != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: role == '房主' ? gold : const Color(0xffa9bfee),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                role,
                style: const TextStyle(color: ink, fontSize: 8),
              ),
            ),
          const SizedBox(height: 3),
          Text(
            u.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: paper, fontSize: 10),
          ),
          Text(
            p.isOnline ? '正在自习' : lastSeen(p.lastSeen),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xffaab2c2), fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget roomView(StudyRoom r) {
    final me = s.residentOf(r, s.currentUser.id);
    final residents = r.residents.where((p) => p.approved).toList()
      ..sort((a, b) {
        int rank(RoomResident p) => p.userId == r.ownerId
            ? -1
            : r.adminIds.contains(p.userId)
            ? r.adminIds.indexOf(p.userId)
            : 999;
        return rank(a).compareTo(rank(b));
      });
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) act(exitRoom);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          SeasonalWindow(season: r.backgroundId),
          if (immersive)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: TextButton.icon(
                  key: const ValueKey('exit-immersive'),
                  style: TextButton.styleFrom(
                    foregroundColor: paper,
                    backgroundColor: const Color(0xaa0a0e1a),
                  ),
                  onPressed: () => setState(() => immersive = false),
                  icon: const Icon(Icons.music_note, size: 13),
                  label: Text(
                    '${StudyStore.musicTracks[r.musicId]} · 轻触返回',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            )
          else ...[
            Positioned(
              top: MediaQuery.paddingOf(context).top + 26,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  roundAction(
                    '返回房间列表',
                    Icons.chevron_left,
                    () => act(exitRoom),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x990a0e1a),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: paper,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${online(r)} 人在线 · ${StudyStore.backgrounds[r.backgroundId]}',
                            style: const TextStyle(color: gold, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  roundAction(
                    '专注计时',
                    Icons.timer_outlined,
                    () => sheet(
                      '专注计时',
                      (ctx, refresh) => [
                        Center(
                          child: Text(
                            time,
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GoldButton(
                          label: focusing ? '休息一下' : '开始专注',
                          onPressed: me?.approved == true
                              ? () {
                                  act(() => focusing = !focusing);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                }
                              : null,
                        ),
                        const Text(
                          '计时仅保存在本次自习中，不影响在线状态。',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  roundAction('房间菜单', Icons.more_horiz, () => roomMenu(r)),
                ],
              ),
            ),
            if (memberWall)
              Positioned(
                top: 92,
                left: 0,
                right: 0,
                bottom: 72,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x330c101e), Color(0xcc0c101e)],
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              '${StudyStore.musicTracks[r.musicId]} · ${online(r)} 人在线',
                              style: const TextStyle(color: gold, fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => memberWall = false),
                            child: const Text(
                              '收起',
                              style: TextStyle(color: paper),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: GridView.count(
                          padding: const EdgeInsets.all(12),
                          crossAxisCount: 4,
                          mainAxisExtent: 116,
                          children: residents
                              .map((p) => member(r, p, large: true))
                              .toList(),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          '各自努力，彼此陪伴',
                          style: TextStyle(
                            color: gold,
                            fontSize: 12,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Positioned(
                right: 12,
                bottom: 310,
                child: TextButton.icon(
                  key: const ValueKey('immersive'),
                  style: TextButton.styleFrom(
                    foregroundColor: paper,
                    backgroundColor: const Color(0x990a0e1a),
                    minimumSize: const Size(60, 28),
                  ),
                  onPressed: () => setState(() => immersive = true),
                  icon: const Icon(Icons.fullscreen, size: 14),
                  label: const Text('沉浸', style: TextStyle(fontSize: 11)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 72,
                height: 228,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xb30a0e1a)],
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '常驻 ${residents.length} 人 · 此刻 ${online(r)} 人在',
                              style: const TextStyle(
                                color: paper,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('all-members'),
                            onPressed: () => setState(() => memberWall = true),
                            child: const Text(
                              '全部成员 ›',
                              style: TextStyle(color: gold, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: GridView.count(
                          padding: EdgeInsets.zero,
                          crossAxisCount: 5,
                          childAspectRatio: .62,
                          children: residents
                              .take(10)
                              .map((p) => member(r, p))
                              .toList(),
                        ),
                      ),
                      if (me?.approved != true)
                        GoldButton(
                          label: me == null ? '申请常驻' : '等待审批',
                          onPressed: me == null
                              ? () => act(() async {
                                  await s.requestJoinRoom(r.id);
                                  notice('常驻申请已提交，等待房主同意');
                                })
                              : null,
                        )
                      else if (r.emojiEnabled)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: ['👏', '💪', '☕', '🌸', '📚', '✨']
                              .map(
                                (e) => Expanded(
                                  child: InkWell(
                                    onTap: () => act(
                                      () => s.sendEmoji(roomId: r.id, emoji: e),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        e,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              height: 52,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: nightCard.copyWith(color: const Color(0xe60e121e)),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 17,
                      backgroundColor: Color(0xff3b3440),
                      child: Icon(Icons.album, color: gold, size: 28),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${StudyStore.musicTracks[r.musicId]} · $time',
                            style: const TextStyle(color: paper, fontSize: 12),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            '场景音效待接入 · 本地专注计时',
                            style: TextStyle(
                              color: Color(0xff9aa3b5),
                              fontSize: 9,
                            ),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: (seconds % 1500) / 1500,
                            minHeight: 2,
                            color: gold,
                            backgroundColor: Color(0xff34394a),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: focusing ? '暂停专注' : '开始专注',
                      onPressed: me?.approved == true
                          ? () => act(() => focusing = !focusing)
                          : null,
                      icon: Icon(
                        focusing ? Icons.pause : Icons.play_arrow,
                        color: gold,
                      ),
                    ),
                    roundAction('环境与歌单', Icons.queue_music, () => roomMenu(r)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void roomMenu(StudyRoom r) => sheet(
    '房间 · ${r.name}',
    (ctx, _) => [
      SelectableText('房间编号：${r.id}'),
      const SizedBox(height: 12),
      if (s.canManageRoom(r))
        GoldButton(
          label: '房间管理 · 背景与音乐',
          onPressed: () {
            if (ctx.mounted) Navigator.pop(ctx);
            manage(r);
          },
        ),
      ...s.emojiEvents
          .where((e) => e.roomId == r.id)
          .toList()
          .reversed
          .take(5)
          .map(
            (e) => ListTile(title: Text('${user(e.userId).name}  ${e.emoji}')),
          ),
      TextButton(
        onPressed: () async {
          if (ctx.mounted) Navigator.pop(ctx);
          await act(exitRoom);
        },
        child: const Text('离开房间（保留常驻身份）'),
      ),
    ],
  );

  String lastSeen(DateTime? time) {
    if (time == null) return '暂未上线';
    final min = DateTime.now().difference(time).inMinutes;
    return min < 1
        ? '刚刚在线'
        : min < 60
        ? '$min 分钟前在线'
        : '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} 在线';
  }

  void createRoom() {
    final name = TextEditingController();
    bool private = false;
    String? badge;
    sheet(
      '创建自己的自习室',
      (ctx, refresh) => [
        if (s.currentUser.isGuest || !s.currentUser.profileComplete)
          const Padding(
            padding: EdgeInsets.only(bottom: 15),
            child: Text('创建房间前，请到「我的」注册并完善昵称、头像。'),
          ),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: '房间名称'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('私密房间'),
          subtitle: const Text('不在公开列表展示，通过编号申请加入'),
          value: private,
          onChanged: (v) => refresh(() => private = v),
        ),
        DropdownButtonFormField<String>(
          initialValue: badge,
          decoration: const InputDecoration(labelText: '必需勋章（可选）'),
          items: [
            const DropdownMenuItem(value: '', child: Text('不设置门槛')),
            ...s.receivedBadges.map(
              (b) => DropdownMenuItem(value: b.id, child: Text(b.name)),
            ),
          ],
          onChanged: (v) => badge = v == '' ? null : v,
        ),
        const SizedBox(height: 10),
        const Text(
          '房主勋章失效后，按管理员排序转让给持有有效勋章的人；无人符合时房间解散。',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => act(() async {
            final r = await s.createRoom(
              name: name.text,
              isPrivate: private,
              requiredBadgeId: badge,
            );
            await enterRoom(r);
            if (ctx.mounted) Navigator.pop(ctx);
          }),
          child: const Text('创建房间'),
        ),
      ],
    );
  }

  void joinPrivate() {
    final c = TextEditingController();
    sheet(
      '通过编号申请加入',
      (ctx, _) => [
        TextField(
          controller: c,
          decoration: const InputDecoration(labelText: '完整房间编号'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => act(() async {
            await s.requestJoinRoom(c.text.trim());
            if (ctx.mounted) Navigator.pop(ctx);
            notice('申请已提交');
          }),
          child: const Text('申请常驻'),
        ),
      ],
    );
  }

  void manage(StudyRoom r) {
    sheet(
      '房间管理',
      (ctx, refresh) {
        r = s.rooms.where((room) => room.id == r.id).firstOrNull ?? r;
        return [
        const Text('环境设置从系统固定选项中选择'),
        DropdownButtonFormField<String>(
          initialValue: r.backgroundId,
          items: StudyStore.backgrounds.entries
              .map((v) => DropdownMenuItem(value: v.key, child: Text(v.value)))
              .toList(),
          onChanged: (v) => act(() async {
            await s.updateRoomAmbience(roomId: r.id, backgroundId: v);
            if (ctx.mounted) refresh(() {});
          }),
        ),
        DropdownButtonFormField<String>(
          initialValue: r.musicId,
          items: StudyStore.musicTracks.entries
              .map((v) => DropdownMenuItem(value: v.key, child: Text(v.value)))
              .toList(),
          onChanged: (v) => act(() async {
            await s.updateRoomAmbience(roomId: r.id, musicId: v);
            if (ctx.mounted) refresh(() {});
          }),
        ),
        SwitchListTile(
          title: const Text('允许表情弹幕'),
          value: r.emojiEnabled,
          onChanged: (v) => act(() async {
            await s.updateRoomAmbience(roomId: r.id, emojiEnabled: v);
            if (ctx.mounted) refresh(() {});
          }),
        ),
        if (r.ownerId == s.currentUser.id) ...[
          heading('常驻申请'),
          ...r.residents
              .where((p) => !p.approved)
              .map(
                (p) => ListTile(
                  title: Text(user(p.userId).name),
                  trailing: Wrap(children: [
                    if (s is RemoteStudyStore) TextButton(
                      onPressed: () => act(() => (s as RemoteStudyStore).rejectResident(r.id, p.userId)),
                      child: const Text('拒绝'),
                    ),
                    TextButton(
                      onPressed: () => act(() async {
                        await s.approveResident(roomId: r.id, userId: p.userId);
                        if (ctx.mounted) refresh(() {});
                      }),
                      child: const Text('同意'),
                    ),
                  ]),
                ),
              ),
          heading('管理员顺序', '顺序决定房主勋章失效时的转让优先级'),
          ...r.adminIds.asMap().entries.map(
            (e) => ListTile(
              leading: Text('${e.key + 1}'),
              title: Text(user(e.value).name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '提高转让优先级',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: e.key == 0
                        ? null
                        : () => act(() async {
                            final ids = List<String>.from(r.adminIds);
                            final id = ids.removeAt(e.key);
                            ids.insert(e.key - 1, id);
                            await s.reorderAdmins(roomId: r.id, userIds: ids);
                            if (ctx.mounted) refresh(() {});
                          }),
                  ),
                  IconButton(
                    tooltip: '移除管理员',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => act(() async {
                      await s.removeAdmin(roomId: r.id, userId: e.value);
                      if (ctx.mounted) refresh(() {});
                    }),
                  ),
                ],
              ),
            ),
          ),
          ...r.residents
              .where(
                (p) =>
                    p.approved &&
                    p.userId != r.ownerId &&
                    !r.adminIds.contains(p.userId),
              )
              .map(
                (p) => ListTile(
                  title: Text(user(p.userId).name),
                  trailing: TextButton(
                    onPressed: () => act(() async {
                      await s.addAdmin(roomId: r.id, userId: p.userId);
                      if (ctx.mounted) refresh(() {});
                    }),
                    child: const Text('设为管理员'),
                  ),
                ),
              ),
        ],
      ]; },
    );
  }

  Widget discover() {
    final rooms = s.rooms.where((r) => !r.isPrivate).toList()
      ..sort((a, b) => online(b).compareTo(online(a)));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  key: const ValueKey('room-search'),
                  controller: roomSearch,
                  style: const TextStyle(color: paper, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '输入完整房间编号',
                    hintStyle: const TextStyle(color: Color(0xff9aa3b5)),
                    fillColor: Colors.white.withValues(alpha: .06),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GoldButton(
              label: '进入',
              onPressed: () => act(() async {
                final r = s.rooms
                    .where((r) => r.id == roomSearch.text.trim())
                    .firstOrNull;
                if (r == null) throw StateError('房间不存在');
                await enterRoom(r);
              }),
            ),
          ],
        ),
        section('公开房间', '按此刻在线人数'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.12,
          children: rooms
              .map(
                (r) => InkWell(
                  onTap: () => enterRoom(r),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: nightCard,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox(
                            width: double.infinity,
                            child: SeasonalWindow(season: r.backgroundId),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 7, 8, 3),
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: paper),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Text(
                            '${online(r)} 人在 · ${user(r.ownerId).name}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xff9aa3b5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        section('自习伙伴', '好友需双方同意'),
        ...s.users
            .where((u) => u.id != s.currentUser.id && !u.isGuest)
            .map(
              (u) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: avatar(u, radius: 18),
                title: Text(
                  u.name,
                  style: const TextStyle(color: paper, fontSize: 13),
                ),
                trailing: const Icon(Icons.chevron_right, color: gold),
                onTap: () => personActions(u),
              ),
            ),
      ],
    );
  }

  void personActions(StudyUser u) {
    sheet(
      u.name,
      (ctx, _) => [
        Center(child: avatar(u, radius: 35)),
        const SizedBox(height: 20),
        if (u.id != s.currentUser.id) ...[
          if (!s.currentUser.friendIds.contains(u.id))
            OutlinedButton(
              onPressed: () => act(() async {
                await s.sendFriendRequest(u.id);
                if (ctx.mounted) Navigator.pop(ctx);
                notice('好友申请已发送');
              }),
              child: const Text('发送好友申请'),
            ),
          FilledButton.icon(
            onPressed: () {
              if (ctx.mounted) Navigator.pop(ctx);
              gift(u);
            },
            icon: const Icon(Icons.card_giftcard),
            label: const Text('赠送头像框'),
          ),
        ],
        const SizedBox(height: 12),
        const Text('这里只有安静的陪伴，不提供私聊。', textAlign: TextAlign.center),
      ],
    );
  }

  Widget profile() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: nightCard,
        child: Row(
          children: [
            avatar(s.currentUser, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.currentUser.name,
                    style: const TextStyle(
                      color: paper,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'ID：${s.currentUser.id}',
                    style: const TextStyle(
                      color: Color(0xff9aa3b5),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.currentUser.isGuest
                        ? '访客 · 注册后创建房间'
                        : s.currentUser.isMember
                        ? '会员'
                        : '普通用户',
                    style: const TextStyle(color: gold, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      profileRow(Icons.person_outline, '个人资料', '昵称与头像', editProfile),
      profileRow(
        Icons.door_front_door_outlined,
        '我的房间',
        '常驻与管理',
        () => setState(() => tab = 0),
      ),
      profileRow(
        Icons.workspace_premium_outlined,
        '我的勋章与礼物',
        '领取 · 发行 · 好友申请',
        () => sheet('我的勋章与礼物', (ctx, refresh) => accountItems()),
      ),
      profileRow(
        Icons.switch_account_outlined,
        '账号登录与注册',
        '当前账号与安全退出',
        switchIdentity,
      ),
      profileRow(
        Icons.info_outline,
        '设置与说明',
        '服务连接与支付说明',
        () => sheet(
          '设置与说明',
          (ctx, _) => [
            const Text('账号、房间和在线状态由服务端管理。支付提供商尚未配置，订单保持待支付。场景音效待接入。'),
          ],
        ),
      ),
    ],
  );
  Widget profileRow(
    IconData icon,
    String title,
    String note,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: action,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: nightCard,
        child: Row(
          children: [
            Icon(icon, color: gold, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: paper, fontSize: 14),
              ),
            ),
            Text(
              note,
              style: const TextStyle(color: Color(0xff9aa3b5), fontSize: 10),
            ),
            const Icon(Icons.chevron_right, size: 17, color: Color(0xff9aa3b5)),
          ],
        ),
      ),
    ),
  );
  List<Widget> accountItems() => [
    heading('我的勋章'),
    Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: newBadge,
          icon: const Icon(Icons.add),
          label: const Text('创建勋章'),
        ),
        OutlinedButton(onPressed: redeem, child: const Text('兑换勋章')),
      ],
    ),
    ...s.receivedBadges.map(
      (b) => ListTile(
        leading: const Icon(Icons.verified_outlined, color: Color(0xffa8742a)),
        title: Text(b.name),
        subtitle: Text(holdingStatus(b, s.currentUser.id)),
      ),
    ),
    heading('我发行的勋章', '兑换码可复制给其他用户'),
    ...s.issuedBadges.map(
      (b) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(badgeStatus(b)),
              SelectableText('兑换码：${b.code}'),
              Text(
                '已领取：${b.recipientIds.map((id) => user(id).name).join('、')}',
              ),
              ...(s is RemoteStudyStore ? (s as RemoteStudyStore).holdings.where((h) => h['badgeId'] == b.id).map((h) => h['userId'] as String) : b.recipientIds).map(
                (id) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(user(id).name),
                  subtitle: Text(holdingStatus(b, id)),
                  trailing: Wrap(children: [
                    if (s is RemoteStudyStore) TextButton(
                      onPressed: () => act(() => (s as RemoteStudyStore).renewHolding(b.id, id)),
                      child: const Text('续期30天')),
                    TextButton(onPressed: () => confirmRemoveHolder(b, id), child: const Text('解除')),
                  ]),
                ),
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: b.code));
                      notice('兑换码已复制');
                    },
                    child: const Text('复制'),
                  ),
                  TextButton(
                    onPressed: () => act(() async {
                      await s.renewBadge(
                        badgeId: b.id,
                        validity: const Duration(days: 30),
                      );
                      notice('有效期已延长 30 天');
                    }),
                    child: const Text('续期 30 天'),
                  ),
                  TextButton(
                    onPressed: () => confirmRevoke(b),
                    child: const Text('撤销勋章'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    heading('好友申请'),
    ...s.friendRequests
        .where(
          (r) =>
              r.toId == s.currentUser.id &&
              r.status.toString().split('.').last == 'pending',
        )
        .map(
          (r) => ListTile(
            title: Text(user(r.fromId).name),
            trailing: Wrap(
              children: [
                TextButton(
                  onPressed: () => act(() => s.declineFriendRequest(r.id)),
                  child: const Text('拒绝'),
                ),
                FilledButton(
                  onPressed: () => act(() => s.acceptFriendRequest(r.id)),
                  child: const Text('同意'),
                ),
              ],
            ),
          ),
        ),
    heading('我送出的订单'),
    ...s.gifts.where((g) => g.senderId == s.currentUser.id).map((g) => ListTile(
      title: Text('${StudyStore.frameCatalog[g.frameId]} → ${user(g.recipientId).name}'),
      subtitle: Text('${g.duration.inDays} 天 · ${giftStatus(g)}'),
    )),
    heading('头像框礼物', '先接受，再佩戴；有效期从接受时开始'),
    ...s.gifts
        .where((g) => g.recipientId == s.currentUser.id)
        .map(
          (g) => ListTile(
            leading: const Icon(Icons.card_giftcard),
            title: Text(
              '${StudyStore.frameCatalog[g.frameId]} · ${g.duration.inDays} 天',
            ),
            subtitle: Text('来自 ${user(g.senderId).name} · ${giftStatus(g)}'),
            trailing: TextButton(
              onPressed: g.status == 'paid' || g.isActiveAt(s.now)
                  ? () => act(() async {
                      if (g.status == 'paid') {
                        await s.acceptGift(g.id);
                      } else {
                        await s.switchFrame(g.id);
                      }
                    })
                  : null,
              child: Text(
                g.status == 'paid'
                    ? '接受'
                    : g.isActiveAt(s.now)
                    ? '佩戴'
                    : giftStatus(g),
              ),
            ),
          ),
        ),
    TextButton(
      onPressed: () => act(() async => await s.switchFrame(null)),
      child: const Text('不佩戴头像框'),
    ),
    const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Text(
        '账号权限以服务器为准。支付暂未开通，待支付订单不会变为可领取礼物。',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    ),
  ];
  void editProfile() {
    if (s is RemoteStudyStore && s.currentUser.isGuest) { switchIdentity(); return; }
    final c = TextEditingController(
      text: s.currentUser.isGuest ? '' : s.currentUser.name,
    );
    String face = s.currentUser.avatar;
    sheet(
      s.currentUser.isGuest ? '注册并完善资料' : '完善个人资料',
      (ctx, refresh) => [
        TextField(
          controller: c,
          decoration: const InputDecoration(labelText: '昵称'),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 8,
          children: ['🙂', '🐱', '🐼', '🦊', '🐰', '🐻']
              .map(
                (e) => ChoiceChip(
                  label: Text(e, style: const TextStyle(fontSize: 26)),
                  selected: face == e,
                  onSelected: (_) => refresh(() => face = e),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => act(() async {
            if (s.currentUser.isGuest) await s.registerGuest(name: c.text);
            await s.updateProfile(name: c.text, avatar: face);
            if (ctx.mounted) Navigator.pop(ctx);
          }),
          child: const Text('保存资料'),
        ),
      ],
    );
  }

  void newBadge() {
    final c = TextEditingController();
    bool lifetime = false;
    sheet(
      '创建勋章',
      (ctx, refresh) => [
        TextField(
          controller: c,
          decoration: const InputDecoration(labelText: '勋章名称'),
        ),
        SwitchListTile(
          title: const Text('终身有效'),
          subtitle: const Text('关闭后有效期为 30 天'),
          value: lifetime,
          onChanged: (v) => refresh(() => lifetime = v),
        ),
        FilledButton(
          onPressed: () => act(() async {
            await s.createBadge(
              name: c.text,
              validity: lifetime ? null : const Duration(days: 30),
            );
            if (ctx.mounted) Navigator.pop(ctx);
          }),
          child: const Text('生成勋章和兑换码'),
        ),
      ],
    );
  }

  void redeem() {
    final c = TextEditingController();
    sheet(
      '领取勋章',
      (ctx, _) => [
        TextField(
          controller: c,
          decoration: const InputDecoration(labelText: '输入兑换码'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => act(() async {
            await s.redeemBadge(c.text.trim());
            if (ctx.mounted) Navigator.pop(ctx);
            notice('勋章已领取');
          }),
          child: const Text('确认兑换'),
        ),
      ],
    );
  }

  void confirmRemoveHolder(StudyBadge b, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('解除 ${user(id).name} 的勋章？'),
        content: const Text('对方将失去准入资格；如果对方是房主，将触发转让或解散。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认解除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      act(() => s.revokeBadgeFromUser(badgeId: b.id, userId: id));
    }
  }

  void confirmRevoke(StudyBadge b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销勋章？'),
        content: const Text('所有领取者将失去此勋章，相关房间可能转让或解散。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤销'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) act(() => s.revokeBadge(b.id));
  }

  void gift(StudyUser u) {
    String frame = StudyStore.frameCatalog.keys.first;
    int days = 7;
    sheet(
      '送给 ${u.name}',
      (ctx, refresh) => [
        const Text('挑一份陪伴的小礼物'),
        const SizedBox(height: 15),
        DropdownButtonFormField<String>(
          initialValue: frame,
          items: StudyStore.frameCatalog.entries
              .map((f) => DropdownMenuItem(value: f.key, child: Text(f.value)))
              .toList(),
          onChanged: (v) => frame = v!,
        ),
        if (s is! RemoteStudyStore) Wrap(
          spacing: 8,
          children: [7, 30, 90]
              .map(
                (d) => ChoiceChip(
                  label: Text('$d 天'),
                  selected: days == d,
                  onSelected: (_) => refresh(() => days = d),
                ),
              )
              .toList(),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('创建待支付订单，价格与有效期以服务端商品配置为准。支付尚未配置，暂不能完成赠送。'),
        ),
        FilledButton(
          onPressed: () => act(() async {
            await s.purchaseGift(
              recipientId: u.id,
              frameId: frame,
              duration: Duration(days: days),
            );
            if (ctx.mounted) Navigator.pop(ctx);
            notice('订单已创建，保持待支付；支付提供商尚未配置');
          }),
          child: const Text('创建待支付订单'),
        ),
      ],
    );
  }

  void switchIdentity() {
    if (s is RemoteStudyStore) {
      final remote = s as RemoteStudyStore;
      final login = TextEditingController();
      final password = TextEditingController();
      final name = TextEditingController(text: s.currentUser.isGuest ? '' : s.currentUser.name);
      bool register = s.currentUser.isGuest;
      sheet('账号登录与注册', (ctx, refresh) => [
        Text('当前：${s.currentUser.name} · ${s.currentUser.isGuest ? "访客" : "已登录"}'),
        if (s.currentUser.isGuest) SwitchListTile(title: const Text('注册并升级当前访客'), value: register, onChanged: (v) => refresh(() => register = v)),
        TextField(controller: login, decoration: const InputDecoration(labelText: '账号'), autocorrect: false),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: '密码（10–256 位）')),
        if (register) TextField(controller: name, decoration: const InputDecoration(labelText: '昵称')),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => act(() async {
          await remote.authenticate(register: register, login: login.text.trim(), password: password.text, name: name.text.trim());
          selected = null;
          focusing = false;
          if (ctx.mounted) Navigator.pop(ctx);
          notice(register ? '注册成功，请完善个人资料' : '登录成功');
        }), child: Text(register ? '注册并升级' : '登录')),
        if (!s.currentUser.isGuest) TextButton(onPressed: () => act(() async {
          await remote.logout(); selected = null; focusing = false;
          if (ctx.mounted) Navigator.pop(ctx);
        }), child: const Text('退出登录')),
      ]).whenComplete(() { login.dispose(); password.dispose(); name.dispose(); });
      return;
    }
    sheet(
      '账号登录与注册',
      (ctx, _) => [
        const Text('用于验证双方审批、勋章领取和收礼流程，不代表真实登录。'),
        ...s.users.map(
          (u) => ListTile(
            leading: avatar(u),
            title: Text(u.name),
            subtitle: Text(
              u.isGuest
                  ? '虚拟访客'
                  : u.isMember
                  ? '会员'
                  : '非会员',
            ),
            onTap: () => act(() async {
              await exitRoom();
              await s.switchUser(u.id);
              if (ctx.mounted) Navigator.pop(ctx);
            }),
          ),
        ),
      ],
    );
  }
}

class SeasonalWindow extends StatelessWidget {
  const SeasonalWindow({super.key, this.season = 'forest'});
  final String season;
  @override
  Widget build(BuildContext context) {
    final foreground = season == 'sea'
        ? 'it_05.webp'
        : season == 'forest'
        ? 'it_06.webp'
        : 'it_04.webp';
    final background = season == 'sea'
        ? 'bg_02.jpg'
        : season == 'forest'
        ? 'bg_03.jpg'
        : season == 'night'
        ? 'bg_06.jpg'
        : 'bg_10.jpg';
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 375,
            height: 667,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xff141c35)),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 30,
                  height: 400,
                  child: Image.asset(
                    'assets/scenes/$background',
                    fit: BoxFit.cover,
                  ),
                ),
                Image.asset('assets/scenes/$foreground', fit: BoxFit.cover),
                const ColoredBox(color: Color(0x33121a38)),
                Positioned(
                  left: season == 'sea'
                      ? -117
                      : season == 'forest'
                      ? -224
                      : 61,
                  top: season == 'sea'
                      ? 192
                      : season == 'forest'
                      ? 222
                      : 205,
                  width: season == 'forest'
                      ? 460
                      : season == 'sea'
                      ? 320
                      : 350,
                  height: season == 'forest'
                      ? 460
                      : season == 'sea'
                      ? 320
                      : 350,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0x66ffce88), Color(0x00ffae5c)],
                      ),
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x400a0e1a),
                        Colors.transparent,
                        Color(0x550a0e1a),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .5 : 1,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xffffe2a6), Color(0xfff0b85c)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0xffa8742a), offset: Offset(0, 3)),
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xff2a1a05),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
