# 公开自用版 App 专属映射验证

适用：macOS 公开组件本地构建；私有键位方案组件存在时沿用原路径。本功能的产品规则见 [按键映射规范](../feature/button-mapping/PRODUCT_SPEC.md#macos-公开自用版-app-专属映射)。

## 准备

- 使用本机固定开发证书构建，覆盖安装到 `~/Applications/SayAll.app`。保留当前遥控器、语音、音频和全局映射；不重跑首次使用向导。
- 蓝牙、输入监控和设备控制权限有效，遥控器已连接。准备两个普通 App，不读取其内部数据。
- 按键页顶部选择全局或 App 专属；添加 App 使用系统选择器。当前编辑对象不会跟随前台切换。

## 手工步骤与判定

1. 升级后先确认原全局按键、音量增益、Fn 语音和输出设备保留，输入监控及设备控制仍有效。任一配置改变或重新弹授权均须记录为失败。
2. 添加 App A，为主页键单击设置一个不同于全局的动作。切换 A，在遥控器上按主页键，应执行专属动作；切换未添加的 B，同键应执行全局动作。每次第一次按键即正确才算通过。
3. A 只改主页键单击，方向键与主页键双击、长按应继承全局。修改某个未覆盖的全局动作后，回到 A 应立即使用新动作。
4. 在 A 把一项“停用此动作”，应不执行，也不能落回全局。点“沿用全局”后应恢复。取消添加 App 不产生配置；重复添加同 App 应选中已有项。
5. A 设置双击后，按第一下并立即切到 B，等待超过双击窗口，不得在 B 补发 A 的单击。按住连发时切换，连发必须停止；松键后下一次新按键可用。
6. App 专属页面的按住方式、快速连按和手势时间标注为全局，不能在专属页意外改写全局。语音键保持原 Fn 行为，真实说话、松键尾音和第三方文字上屏仍需验证。
7. 重启 SayAll，重复步骤 2–4。删除 A 的专属配置，应恢复全局；删除确认取消时原配置保留。不同遥控器的覆盖不能串用。
8. 导出完整配置、修改专属映射再导入，应恢复专属配置。旧版本拒绝含专属映射的格式 3；不含专属映射仍用格式 2。导入取消不写入，损坏配置不得覆盖原内容。
9. 中文/英文、浅色/深色下检查全局、App 专属、编辑器、继承与覆盖、停用、删除确认、保存失败状态；生产最小窗口逐项检查导航和滚动，中文不小于 12pt。

## 自动化与日志

```sh
SAYALL_PRIVATE_PLATFORM_MODE=public swift test --disable-keychain --filter 'ApplicationButtonMappingsTests|RemoteButtonsTests|SettingsPageRegressionTests|CompleteConfigurationBackupTests|GestureLearningPersistenceTests'
scripts/verify-localizations.sh
SAYALL_LOCAL_BUILD_MODE=public scripts/package-local-test-app.sh
```

- `APP MAPPING action=activate ... scope=application|global` 只证明前台映射选择。
- `action=write`、`action=save ... result=stored` 只证明配置保存。
- `action=dispatch ... scope=application|global` 只证明派发解析；结合后续 `HID BUTTON`、执行结果和实际 App 响应判断，不得将解析当成最终成功。
- `action=cancel_pending ... reason=frontmost_changed` 标记取消普通按键的延迟执行。语音事件须单独核对。
- `action=load ... result=unavailable` 表示存储不可读，界面保留错误并阻止覆盖。修复后使用重新加载；日志不含 App 身份、路径、快捷键内容或设备标识。
- 本地 public 构建日志位于用户的 `Library/Logs/RemoteMic/runtime.log`；检查当前 PID 与 Build，避免混入旧进程。

## 本次验证边界

- 2026-11-12：270 项定向测试通过，本地化检查、治理检查、相关 Markdown 链接和 `git diff --check` 通过。覆盖前台匹配与未知目标、设备/手势隔离、继承/停用/恢复、关闭映射开关、持久化、坏数据保护、完整备份格式 3 往返、模拟 HID 原生透传与切换时取消延迟动作。
- Release 构建及 App 校验通过；本机 `2.0.0 (8)` 已覆盖安装并启动。新旧 designated requirement 一致，`codesign --verify --deep --strict` 通过。32 项按键、语音、音频、设备和向导配置语义一致；当前进程日志确认 `input=true accessibility=true`。
- 中英文、浅深色及专属编辑器采用已安装构建的生产视图离屏渲染，窗口不显示；PNG 尺寸和摘要见 [证据索引](../Screenshots/local-app-mappings/manifest.json)。图片保存在本机 Downloads 下，未公开上传。
- 离屏生产视图截图只证明布局，不等于真实窗口点击。
- 按用户要求使用终端，不自动切换或点击真实 App；真实遥控器跨 App 动作、权限和第三方语音结果由用户操作后结合日志验收，未完成前保持待验证。
