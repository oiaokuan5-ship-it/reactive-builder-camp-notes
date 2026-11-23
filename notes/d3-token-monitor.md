# 第一次部署：监控 Sepolia 上的代币转账

2026-11-23（Asia/Shanghai）在 Lasna 测试网部署了一个 Reactive 合约 `TokenMonitor`，监听我在 Sepolia 上自己部署的测试代币 CTT 的 `Transfer` 事件。代码在 [`code/wcb-labs`](../code/wcb-labs)。

**一句话过滤条件**：只订阅 Sepolia（chainId 11155111）上 CTT 合约 `0x861e…EA7c` 发出的 ERC-20 `Transfer`（topic0 = `0xddf252ad…b3ef`），topic1～3 都用 `REACTIVE_IGNORE` 通配；处理满 3 笔后自动退订。

## 地址

| 角色 | 链 | 地址 |
|---|---|---|
| 测试代币 CTT（源合约） | Sepolia | [0x861e1c26634583b3bFe5b1e3CeEb8e0d906EEA7c](https://sepolia.etherscan.io/address/0x861e1c26634583b3bFe5b1e3CeEb8e0d906EEA7c) |
| TokenMonitor（Reactive 合约） | Lasna | [0x9497A7eF140DE44C98479Ec14033E00774cE5870](https://lasna.reactscan.net/address/0x9497A7eF140DE44C98479Ec14033E00774cE5870) |

## 交易

| 步骤 | 交易 |
|---|---|
| 部署 CTT（Sepolia） | [0xbf246933…49d68](https://sepolia.etherscan.io/tx/0xbf2469330f13cf5d58dd040ad4280de5cb88930cd4901b4bbe9c101e52349d68) |
| 部署 TokenMonitor 并充值 0.1 lREACT（Lasna） | [0xddd30a61…6af86](https://lasna.reactscan.net/tx/0xddd30a614a98ba1ccd4164e9e3868d75750cc3b27270c8eedefc93605fe6af86) |
| 触发 1：转 5 CTT（Sepolia） | [0xdf870396…1f9fc](https://sepolia.etherscan.io/tx/0xdf8703960b653e202323a5f249088ab62215abd2eee4e3469bcfc124eec1f9fc) |
| → react() 1（Lasna，emit TransferSeen） | [0xc4833036…a99b2e](https://lasna.reactscan.net/tx/0xc4833036eba0b8b5b08a471edd8f0ab174d046bd92a7844c312390e51ea99b2e) |
| 触发 2：转 7 CTT（Sepolia） | [0xa4a4a074…81ec3](https://sepolia.etherscan.io/tx/0xa4a4a0740158f9220ad64cfd5a96aab7a6f94ee79925e58c14d047ee56681ec3) |
| → react() 2（Lasna） | [0x73bb451d…be657](https://lasna.reactscan.net/tx/0x73bb451d6d40f37fa43373426e4bd480b1d4f4bdc8e1815ed10424cb3a6be657) |
| 触发 3：转 3 CTT（Sepolia） | [0xcb5dbf13…38436](https://sepolia.etherscan.io/tx/0xcb5dbf132f44d8e180de6be7f9dfe540a281e8b598e9f44a8679b18d23038436) |
| → react() 3（Lasna，emit TransferSeen + Exhausted，自动退订） | [0xa58880a9…e84bd](https://lasna.reactscan.net/tx/0xa58880a9876ea5bef965c3cffe5c591a9b1733b28fec73faa29b62f227fe84bd) |

react() 交易是用 `cast logs --address 0x9497…5870 -r https://lasna-rpc.rnk.dev/` 查 `TransferSeen` 事件找到的；每条事件的 data 里带着对应 Sepolia 转账的 txHash，能一一对上。

## 链上读回

```
seenCount()  = 3
remaining()  = 0          # 已退订
turnover()   = 15e18      # 5 + 7 + 3 CTT
debt(0x9497…5870) = 0
合约余额：0.1 → 0.0511 lREACT（3 次 react() 约 0.049 lREACT，平均每次约 0.016）
```

## 学到的

- 订阅只能等值匹配：这里把「合约地址」写死成自己的代币，避免像 Xfers 示例那样订阅 `address(0)`（Sepolia 全部代币）导致 react() 被频繁调用、很快扣光余额。
- 金额判断只能在 react() 里做；过滤用 `return` 而不是 `revert`（revert 照样收费）。
- 次数上限 `remaining`：每处理一笔减 1，归零时用和订阅完全相同的参数 `unsubscribe`，另有 owner 的 `stop()` 手动刹车。
- 测试：`forge test` 24 passed（含 TokenMonitor 7 条：订阅参数、onlySystem、他币/他链/非 Transfer 忽略、上限后退订、解码）。
