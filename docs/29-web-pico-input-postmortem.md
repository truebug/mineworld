# 29 · Web / Pico 输入尝试复盘（已冻结）

| 字段 | 值 |
|------|-----|
| **状态** | Frozen / Abandoned |
| **日期** | 2026-08-11 |
| **基线** | 键鼠可用；Web **不**支持摇杆/虚拟盘 |
| **现网** | 以本会话回滚后的 `deploy_playground.sh` 全量发版为准 |

## 产品结论（给下一任 Agent）

**暂停在 Godot Web（2D Hub / playground）里接入 Pico 左右摇杆。**  
当前正式产品态：**桌面键鼠 only**。真 VR 双手柄继续走独立 `/xr`，不要塞进 2D Hub。

## 为何放弃（已复现事实）

1. **Pico 2D Browser ≠ Gamepad**  
   物理摇杆被映射成**激光/鼠标光标**（扳机≈LMB，推杆≈拖视角）。Godot `InputMap` Joy 轴（P1）在 Pico 上基本吃不到「左移右转向」。

2. **DOM 虚拟盘（`mw_touch_pad.js`，`cea3658` 起）已证明有害**  
   - 锁 `#canvas { pointer-events: none }` → 桌面鼠标死。  
   - 盘开着时**解锁** canvas → Hub `hub life` 后单线程卡死（对照：`MW_BUILD` 115503 只改 JS 解锁即卡，回退即恢复）。  
   - 禁止再走「DOM 叠层 + 锁/解锁 canvas」修 Pico。

3. **引擎内 VirtualJoystick / 自绘 `MWStickPad`（P2）未交付可用体验**  
   - 默认 VirtualJoystick 主题偏黑，暗色 Hub 上几乎看不见。  
   - 自绘高对比盘仍未在 Pico 上稳定被用户看到/确认可用。  
   - 用户决定：**先停，换 Agent 再试**；本仓回到键鼠基线。

## 已回滚 / 禁止再引入

| 项 | 状态 |
|----|------|
| `godot/spike/web/mw_touch_pad.js` | **删除**，勿恢复 |
| shell / export 注入 touch pad | **去掉** |
| `MWTouchSticks` / `MWStickPad` | **删除** |
| `camera_rig` canvas 锁 / `ignore_mouse_look` Pico 特例 | **去掉** |
| Input Map Joy 轴（P1） | **去掉**（仅保留键位） |
| 正式发版 | 只用 `scripts/deploy_playground.sh` 全量导出 |

## 可进基线（历史锚点）

- 代码：撤盘后对齐 `cea3658^` 输入路径（无 DOM 盘）；会话中可进确认含 `110ca66` 族与回撤后的 `MW_BUILD=20260811-123551` 一带。  
- 卡死对照：`docs/19-changelog.md` 2026-08-11「canvas 解锁会卡死」条目。

## 若下一任仍要做 Pico / 摇杆（建议方向，未实现）

1. **通道分离（强制）**  
   - A 桌面：键鼠（现状）。  
   - B Pico 2D：假定物理杆=指针，**不要**当 `navigator.getGamepads()`。  
   - C 真 XR：`/xr` + `XRInputSource.gamepad`（W3C：XR gamepad ∉ `getGamepads()`）。

2. **不要碰 canvas CSS 锁**；卡死优先回滚，再小步完整发版。

3. **可见性验收先于手感**：任何 on-screen 盘必须在 Pico 实机截图确认「肉眼可见」再谈映射。

4. 可选：独立轻量 HTML 壳 + 仅转发语义动作，与 Godot 场景解耦——但须单独 ADR，且不得锁 `#canvas`。

## 参考

- Godot：[Exporting for Web · Gamepads](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)（需先按键才检测）  
- Godot 4.7：`VirtualJoystick`（主题 StyleBox；默认色曾偏黑）  
- W3C：[WebXR Gamepads Module](https://www.w3.org/TR/webxr-gamepads-module/)  
- 仓内：`docs/19-changelog.md`（2026-08-11 多条）、会话 canvas `web-input-replan.canvas.tsx`（若仍在本机 Cursor canvases）
