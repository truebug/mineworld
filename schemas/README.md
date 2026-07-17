# JSON Schema 草案

与 `docs/` 中协议、契约文档对应，评审通过后作为 SSOT。

| 文件 | 文档 |
|------|------|
| `scene-contract.v0.json` | [02-scene-contract.md](../docs/02-scene-contract.md) |
| `ws-messages.v0.json` | [03-websocket-protocol.md](../docs/03-websocket-protocol.md)（待建） |
| `recording-session.v0.json` | [04-data-collection.md](../docs/04-data-collection.md)（待建） |

校验示例（待安装 `ajv-cli` 或同类工具）：

```bash
ajv validate -s schemas/scene-contract.v0.json -d examples/contracts/tutorial_01.json
```
