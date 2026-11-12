# 映射关闭时普通按键无法完成向导

- 时间：2026-11-12
- 状态：修复候选，待真实按键复验
- 范围：macOS build 3，实体小米遥控器，controls 页，自定义映射关闭
- 证据：当前进程权限均为 true；14:42:54–55（北京时间）HID accepted 收到 down、right、ok，但 tested_button_count=0；HID START 显示 back_only=true。
- 根因：processParsedReport 在 back-only 分支先过滤为返回键，再走不调用 onButtonPressed 的处理函数，普通键无法进入向导观察。
- 修复：仅 controls/xiaomi 来源在 back-only 分支将真实新按下通知现有观察回调并抑制动作；其他阶段仍保留原返回键行为，不改变 customMappingEnabled 或已有映射。
- 验证：扩展已有 back-only 回归覆盖向导观察、重复报告去重、返回键动作抑制及退出恢复。真实设备验证由用户按键，Agent 仅通过终端检查日志。

自动化结果：修复前扩展的原有 back-only 用例失败（观察计数 0，并发生向导内返回键动作）；修复后 `swift test --disable-keychain --filter 'RemoteButtonsTests|OnboardingFlowTests'` 共 288 项通过。安装及真实按键结果待现场补充。
