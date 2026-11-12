# 无屏配置首次发现已连接遥控器失败

- 时间：2026-11-12
- 状态：发现问题已修复，完整语音配置待音频驱动及真实验收
- 范围：macOS 个人公开开发包，Agent 配置命令
- 原始证据：安装副本 2.0.0 build 2 返回 `not_found`、`reason=connected_remote`、空 candidates；系统 Bluetooth 报告已连接小米遥控器，公开 IOHIDManager 精确 VID/PID 枚举返回 1 个接口。
- 日志：本地 runtime.log 有 AI_CONFIG 请求；命令立即 exit，异步日志未留下终态，因此以命令 JSON 与退出码作为失败证据。
- 根因：`connectedRemoteCandidates` 仅遍历保存的设备档案，不枚举当前硬件；首次运行未绑定档案时无法发现系统已连接设备。
- 最小修复：命令使用只读 HID 枚举和现有指纹规则识别当前小米候选、去重、关联已有档案；不打开或独占 HID，不注册按键回调，不把离线小米档案当连接状态；保留私有来源的既有路径。
- 验证：公开编译、Onboarding 现有定向测试、本地包校验和安装命令复验；111 项 Onboarding 测试通过；公开 Release 构建、包校验及安装通过，build 3。安装副本自动配置返回 `controlSource=xiaomi_remote`、`voiceTool=doubao`、`not_found/audio_device`，证明原始设备发现阻断已消除；公开系统音频枚举确认缺少受支持的虚拟设备。用户已授权安装 SayAll 系统音频驱动，管理员密码仍需本人提供。
- 边界：发现设备只允许准备配置，不能证明按键、音频、文字成功。私有来源和跨平台设备矩阵不在本次实测范围。未读取第三方私有配置，未操作窗口。
