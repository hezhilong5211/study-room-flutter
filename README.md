# Study Room Flutter · 一起自习

Flutter 自习室客户端，配套 Python / SQLite API 和浏览器后台管理台。客户端使用 Flutter 原生组件；后台位于 `server/static/`。参考页面：https://wechat.jiuyang.wang/anli/1011/2/seasons/index.html 。当前参考浏览器截图为空白，未完成严格 UX 或逐像素对比。

`assets/scenes/` 的七张场景图来自参考站点 `https://wechat.jiuyang.wang/anli/1011/2/_img/`（`it_04.webp`、`it_05.webp`、`it_06.webp`、`bg_10.jpg`、`bg_02.jpg`、`bg_03.jpg`、`bg_06.jpg`）。原站版权标注为「云创游科技（西安）分公司」，正式发布前需确认授权。

## 后端与后台启动

需要 Python 3.10+，运行时无第三方依赖。从项目根目录执行：

```sh
# 首次创建 admin 账号时设置至少 12 位密码；请自行输入，不要写入仓库。
read -rs -p 'Admin password: ' STUDY_ADMIN_PASSWORD
export STUDY_ADMIN_PASSWORD
export STUDY_ALLOWED_ORIGINS=http://localhost:7357
python3 server/app.py --host 127.0.0.1 --port 8080 --db /tmp/study-room.sqlite
```

打开 `http://127.0.0.1:8080/admin`，账号为 `admin`。数据库需要放在可持久保存的位置；上述 `/tmp` 仅适合本地试用。重启沿用同一数据库和已有账号，环境变量不会重置已有管理员密码。普通注册保留 `admin` 名称，不可创建或升级成系统管理员。首次启动未提供密码时不会创建管理员。

本地开发如需测试模拟支付，在启动命令末尾增加 `--development`，并使用独立数据库。生产模式默认关闭模拟支付。公网部署需要 HTTPS 反向代理，配置 `STUDY_ALLOWED_ORIGINS` 为实际客户端和管理站点的准确来源（逗号分隔，无尾部斜杠）；示例 Python HTTP 服务不应直接作为公网生产网关。

## Flutter 启动

安装 Flutter 3.35 或更新 stable 版本，先启动后端：

```sh
flutter pub get
flutter run -d chrome --web-port 7357 --dart-define=STUDY_API_URL=http://localhost:8080
```

Android 模拟器的服务地址通常使用 `http://10.0.2.2:8080`；真机需使用可访问的局域网地址并按需将后端绑定为 `--host 0.0.0.0`。iOS 需要 macOS、Xcode 与签名配置。发布环境使用 HTTPS，并核对平台网络策略。应用 ID 为示例 `com.studyroom`，上架前须替换。

## 已实现后端能力

- 访客、注册升级、密码登录、会话注销；SQLite 持久化与后台审计。
- 公开/私密、会员/勋章房间；所有房间的非房主用户进入、心跳和表情操作均检查常驻审批。私密房间不向未批准者返回房间详情。
- 房主审批、管理员优先级、背景/音乐/表情设置；资格失效后按顺序转让，无合格继任者则解散。
- 勋章定义与个人领取记录独立有效期，续期、撤销与准入校验。
- 双向同意的好友申请；头像框订单、领取计时、切换、过期清除。
- 后台用户停用和会员设置、房间管理和审批、勋章管理、订单取消、资源配置和审计列表。

会员 `days: null` 表示永久，保存为年 9999 的远期 Unix 秒时间戳，以保持 Flutter 的数值到期契约；`days: 0` 取消会员，`memberUntil: null` 表示非会员。旧数据库中已经错误保存成 null 的永久会员与非会员无法区分，须管理员重新授权。房间删除同步清理 `residents`、`presence`、`events`，防止幽灵审批。

## 验证

```sh
python3 -m unittest discover -s server -v
flutter analyze
flutter test
flutter build web
```

2026-10-17 本次后端实测：Python 共 21 项通过（10 项服务层回归，10 项复用业务回归经过真实 HTTP socket/JSON 边界，1 项 HTTP 认证、来源限制和管理员边界测试）。部分账号准备、数据库到期注入和重启场景仍直接调用 Service，并非每一个步骤都经过 HTTP。覆盖永久会员、房间删除清理、常驻审批、私密房间过滤、保留管理员名、生产模式模拟支付权益阻断，以及好友、勋章、赠礼、持久化等。

实际 Chromium 后台测试脚本为 `server/browser_test.cjs`。需要 Node.js（支持 fetch）、Playwright Node 包及 Chromium，无需 Python Playwright。在单独终端启动测试服务：

```sh
STUDY_ADMIN_PASSWORD=browser-test-password python3 server/app.py --port 8088 --db /tmp/study-browser-test.sqlite --development
# 第二个终端；按实际安装位置设置 NODE_PATH / CHROMIUM_PATH。
NODE_PATH=/opt/zcode-skill-node/node_modules \
CHROMIUM_PATH=/data/home/.cache/web-screenshot/chromium/chromium \
node server/browser_test.cjs
```

可通过 `STUDY_TEST_URL`、`STUDY_TEST_PASSWORD` 指定测试地址和密码。此脚本会创建测试账号/房间，只能用于隔离测试数据库。实测通过错误密码提示、管理员登录、定期/永久会员保存、永久会员创建会员房、房间环境保存及解散、全部管理标签页、390px 移动宽度无页面横向溢出、注销与无页面 JavaScript 异常。截图写入 `/tmp/study-admin-desktop.png` 和 `/tmp/study-admin-mobile.png`。后台浏览器通过不代表 Flutter 浏览器通过，也不代表参考 UX 一致。

2026-10-17 Flutter 接续验证：对当前工作区运行完整 Dart analysis server，结果为 **0 issues**（复用 `/tmp/analyze-study.py`，将分析根目录改为当前仓库，768 MB 堆上限）。随后单并发执行全部 Flutter 测试，结果为 **21 项全部通过，退出码 0**：15 项业务模型测试、4 项 RemoteStudyStore 测试、2 项移动尺寸组件测试（375×667、320×568）。`test/remote_store_test.dart` 中的真实 HTTP 用例启动独立 Python 服务与临时 SQLite，使用两个 RemoteStudyStore 验证访客升级、注册/登录/注销、资料、勋章领取和撤销、房间申请审批、在线状态和表情、好友同意，以及订单保持 pending 且不可领取；其余 3 项覆盖快照映射、请求队列错误恢复与待支付权益。组件测试使用本地 StudyStore，并非远程服务 UI 端到端测试。

本环境复用 `/tmp/flutter-tools.dill` 绕过 Flutter 启动工具编译；临时 SDK 根目录尝试停留在启动阶段后主动停止，改用实际 SDK 根目录、禁用版本检查后完成测试。成功命令如下（临时工具路径仅适用于本次环境）：

```sh
CI=true FLUTTER_ROOT=/data/home/.local/flutter \
  /data/home/.local/flutter/bin/cache/dart-sdk/bin/dart --old_gen_heap_size=768 \
  /tmp/flutter-tools.dill --verbose --suppress-analytics --no-version-check \
  test --no-pub --concurrency=1 --reporter=expanded
```

本轮未重新验证 Flutter Web 发布构建、Flutter 浏览器远程 UI 闭环、Android/iOS 真机或商店发布；已有后台浏览器结果不能替代这些验证。本轮未修改 `server/`，未重新运行其独立 21 项测试或后台浏览器脚本。

## 当前限制

- 未接入真实支付商户、支付回调验签、退款或对账。生产支付接口返回 503，订单保持待支付；开发订单标记为 `development-simulation`。生产模式禁止其领取、佩戴，并在 sweep 清除已佩戴模拟权益。模拟交易不能作为真实到账证明。
- 会员由管理员授权，尚无订阅购买流程；勋章续期不扣款。资源 URL 配置不等于已验证真实音频播放或完整内容交付。
- 客户端约每 5 秒轮询；在线状态基于心跳，35 秒后显示离线；事件保留约 300 秒，服务后台每 5 秒 sweep。没有 WebSocket 推送，短暂网络中断与轮询间隔会产生可见延迟，不能承诺毫秒级实时。
- 管理台手动刷新列表；本服务采用单进程锁和 SQLite，未做生产负载、高可用、备份恢复、短信/邮件账号找回及正式安全验收。

## 代码入口

- `server/app.py`：认证、业务 API、持久化、定时维护与静态后台服务。
- `server/static/`：后台页面、样式及操作表单。
- `server/test_app.py`、`server/browser_test.cjs`：API 回归与真实浏览器测试。
- `lib/main.dart`、`lib/domain.dart`、`lib/remote_store.dart`：Flutter 页面、业务模型和服务接入。
- `test/`：Flutter 业务与页面测试。
