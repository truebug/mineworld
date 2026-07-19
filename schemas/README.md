# Schema 约定与扩展规则

| 字段 | 值 |
|------|-----|
| **状态** | Accepted（随 2026-07-17 POC 冻结） |
| **SSOT** | 本目录 JSON Schema（draft 2020-12） |

---

## 文件

| 文件 | 文档 | 用途 |
|------|------|------|
| [`scene-contract.v0.json`](scene-contract.v0.json) | [02](../docs/02-scene-contract.md) | 关卡 → MuJoCo 世界 |
| [`ws-messages.v0.json`](ws-messages.v0.json) | [03](../docs/03-websocket-protocol.md) | WebSocket 信封与各 type |
| [`recording-session.v0.json`](recording-session.v0.json) | [04](../docs/04-data-collection.md) | `header.json` + `frames.jsonl` 行 |
| [`common.v0.json`](common.v0.json) | — | 共享 `$defs`（位姿、单位、扩展袋） |

---

## 扩展性原则（实现必须遵守）

1. **信封稳定、载荷可长**：顶层字段少而稳；新能力进 `payload` / `detail` / `extensions`。
2. **开放枚举**：已知值写在 `enum` 的文档与示例里；Schema 用 `string` + 可选 `examples`，或 `anyOf: [enum, pattern]`，避免新 `event_type` 就炸校验。
3. **`extensions` 袋**：任意对象，`additionalProperties: true`。约定键名 `vendor.*` 或 `mw.*`（如 `mw.debug`）。消费者**忽略未知键**。
4. **禁止**在 v0 载荷上设 `additionalProperties: false`（信封 `type/session_id/...` 可严；业务体要松）。
5. **版本**：
   - 文件名 `*.v0.json` = 主版本族；
   - 实例内 `protocol_version` / `contract_version` / `recording_version` 用 **`"0.1"`** 起；
   - **兼容扩展**（只加可选字段）：升 patch/`0.1`→`0.2`，旧客户端忽略新字段；
   - **破坏变更**：升 `1.0` 或新文件 `*.v1.json`，Gateway `hello` 协商拒绝。
6. **判别器**：消息靠 `type`；cmd 靠 `action` 或 `control_mode`；契约实体靠 `kind`/`type`。
7. **坐标**：默认 **米 · 右手 · Z-up**；若某消息带 `frame`，以该字段为准。

---

## POC 冻结频率（T0.6）

| 参数 | 值 | 出现位置 |
|------|-----|----------|
| `dt` | `0.02` | `hello.payload.dt`、recording header |
| `sim_hz` | `50` | `= 1/dt` |
| `state_hz` | `20` | state 广播；录制可更高（`record_every_n_ticks`） |

---

## 校验示例

```bash
# 需安装: npm i -g ajv-cli
ajv validate -s schemas/scene-contract.v0.json -d examples/contracts/demo_city.json -c ajv-formats
ajv validate -s schemas/scene-contract.v0.json -d examples/contracts/tutorial_01.json -c ajv-formats
ajv validate -s schemas/ws-messages.v0.json -d examples/ws/hello.json
ajv validate -s schemas/recording-session.v0.json#/$defs/header -d examples/recordings/sample_header.json
```

Python（可选）：

```bash
pip install jsonschema
python scripts/validate_schemas.py  # Phase 1 可补
```
