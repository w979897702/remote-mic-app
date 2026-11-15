# RC001 长按语音续期实验

## 范围与准备

2026-11-15 本机候选实验，macOS、小米蓝牙遥控器 2（DIS 型号 RC001）、豆包输入法。仅验证 ATVV v1.0 普通物理长按会话的续期，不能宣称 Windows、RC003 或其他硬件已通过。没有新增硬件能力声明。

实验开关 `SayAllRC001VoiceExtendExperiment` 默认缺失/关闭。本次经用户授权使用 public 本机测试包、Apple Development 签名；私有组件不可用，不是分发候选。安装位置为 `~/Applications/SayAll.app`，沿用已有权限与虚拟麦克风设置。

启动后按下立即沿原路径收音；首个真实 PCM 后每 10 秒提交当前会话的 `MIC_EXTEND`。松键、关闭请求、断连或会话重置取消续期，不自动重开麦克风，不修改 Fn、音频排空或时长上限。53/57 秒提醒保留，只代表原硬件边界，不表示实验失败。

## 操作与判定

1. 确认 RC001 已连接，SayAll 与豆包使用同一虚拟麦克风，输入框已聚焦。先说一段短句再松键，首尾文字应完整。
2. 持续按住语音键说话 125 秒，在 55、65、115、125 秒附近各说一句可辨认的短句。不要中途松键。
3. 松键后应结束同一次语音输入，末句完整；再次按下说短句，应立即开始新会话。
4. 若 60 秒附近仍停止，记下北京时间和现象，停止本轮；不要将发送命令日志视为续期成功。

通过必须同时满足：超过 120 秒仍收到真实 PCM、目标工具持续接收文字、松键结束、尾音自然排空。`RC001 VOICE EXTEND ... result=submitted remote_ack=unavailable` 只证明提交蓝牙写入，不代表固件接受。最终同一 `operation_id` 的 `ATVV AUDIO diagnostic` 应有 `completion=normal`、`dropped_samples=0`、`interrupted_samples=0`、`pending_samples=0`，播放与调度样本一致。

失败包括：60 秒仍停止、只有控制消息没有音频、文字中断或首尾字丢失、松键后继续收音、重复 Fn 或额外会话、断连后无法恢复。协议停止事件另记录 `remote_reason`（十进制）；8 表示协议定义的传输超时，2 表示松键，不能据此假定所有固件完全遵循规范。

## 稳定功能与异常回归

- 极速按下/松开 10 次、正常短句 10 次、快速连续两句，检查首字、尾字和会话隔离。
- 收音中断开蓝牙、恢复连接、再说一句；不得残留续期或按键状态。
- 普通遥控器按键和目标 App 切换后第一次语音保持原行为。
- 开关缺失、明确关闭、开启、使用后关闭分别验证；关闭后不应出现续期提交日志，普通会话仍可正常开始与结束。
- 有 RC003 时交替使用两台设备；RC003 不得发出本实验命令。未持有设备时记为未验证。

## 日志与关闭实验

通过 SayAll 的日志目录入口保留本轮完整日志；本机无诊断公钥时为 `~/Library/Logs/RemoteMic/runtime.log`。记录开始/停止时间、型号、目标工具和实际文字是否完整，无需提供语音内容。

退出 SayAll 后执行 `defaults delete com.hd838a.RemoteMic SayAllRC001VoiceExtendExperiment`，重新打开即可恢复默认行为。显式关闭使用 `defaults write com.hd838a.RemoteMic SayAllRC001VoiceExtendExperiment -bool false`，开启使用同一命令的 `true`。以安装包实际 Bundle ID 为准。

## 验证结果与边界

- `SAYALL_PRIVATE_PLATFORM_MODE=public swift test --disable-keychain --filter 'RC001VoiceExtensionTests|ATVVProtocolTests|ATVVAudioDiagnosticsTests|BluetoothLifecycleTests|CoreVoiceInputJourneyTests|VoiceFnTapSessionControllerTests'`：94 项通过（含 4 项续期生命周期测试）。
- `bash scripts/verify-repository-governance.sh`、本次 Markdown 相对链接与 `git diff --check`：通过。
- `SKIP_SWIFT_PACKAGE_BUILD=1 scripts/test.sh`：未通过。当前基线脚本未列入 `ApplicationButtonMappingStore` 等依赖源码，导致 AppSettings 类型无法解析；这些文件本次没有修改。SwiftPM 定向测试正常编译并通过。
- Release 构建、Apple Development 签名、`codesign --verify --deep --strict` 和 `verify-app.sh`：通过；本机候选版本 2.0.0（Build 11），source_commit=e4421bb36a8d5d856b0cd3f209b622517aa2b135，dirty=true。
- 代理未操作实体遥控器；两分钟续期、松键尾字、异常恢复由用户实测，当前均待验证。
- 原始证据：2026-11-15 17:36:48 至 17:37:48（北京时间），RC001 会话 108 持续 59985ms、`reason=remote_stop`、`host_close_requests=0`；用户确认全程未松键。
