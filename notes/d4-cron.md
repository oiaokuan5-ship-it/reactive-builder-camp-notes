# 场景小实验：定时任务（Cron）+ 次数上限

2026-11-23（Asia/Shanghai）选了「定时任务」：Lasna 上的 Reactive 合约 `CronTicker` 订阅 Cron100，每个 tick 请求一次回调到 Sepolia 的 `CronReceiver`，**最多 3 次后自动退订**。代码在 [`code/wcb-labs`](../code/wcb-labs)。

## 地址

| 角色 | 链 | 地址 |
|---|---|---|
| CronTicker（Reactive 合约，MAX_TICKS = 3） | Lasna | [0x861e1c26634583b3bFe5b1e3CeEb8e0d906EEA7c](https://lasna.reactscan.net/address/0x861e1c26634583b3bFe5b1e3CeEb8e0d906EEA7c) |
| CronReceiver（回调合约） | Sepolia | [0xa2a8eAA0d02981eD6D1170a322b0b2A8f4362405](https://sepolia.etherscan.io/address/0xa2a8eAA0d02981eD6D1170a322b0b2A8f4362405) |

（Lasna 上的 CronTicker 和 Sepolia 上的 CTT 代币地址相同，只是同一钱包在两条链 nonce 碰巧一样，两者无关。）

## 触发交易（Cron tick → react() → Sepolia 回调）

| tick | Lasna react()（emit Tick） | 时间 | Sepolia 回调（emit CronHandled） | 时间 |
|---|---|---|---|---|
| 1 | [0xbb3b135d…f0453](https://lasna.reactscan.net/tx/0xbb3b135d544876be48e199233908ee404080c815481fab2227ad9decd11f0453) | 11:05:13 | [0x30e5f284…d8921](https://sepolia.etherscan.io/tx/0x30e5f284bd5d362e5e4e78021e1002d36a89a86b9b7be42efefa26345e0d8921) | 11:05:24 |
| 2 | [0x90a921e1…9b067d](https://lasna.reactscan.net/tx/0x90a921e1da1aba9b173242b08a2b927c5a93c04b7b21324d57255406649b067d) | 11:07:01 | [0x3beca178…cb191](https://sepolia.etherscan.io/tx/0x3beca1781722cada2ae63540618a9c7cf8c66c043599d4f1b23cb26567ccb191) | 11:07:12 |
| 3（最后一次，emit Stopped 并退订） | [0x20524c19…92dc13](https://lasna.reactscan.net/tx/0x20524c198486ac37204b21b5a060e5e45956f2d2b6eac89846814db0f392dc13) | 11:08:48 | [0x27250654…1d0a7](https://sepolia.etherscan.io/tx/0x27250654041af454b120fc96f5c15a30f194bdaa5f23b2bd9d574d016b01d0a7) | 11:09:00 |

时间为区块时间（Asia/Shanghai）。Cron100 实测间隔约 108 秒；react() 到 Sepolia 回调约 11–12 秒。

设置交易：部署 [0xb11dd4c9…9c3c4](https://lasna.reactscan.net/tx/0xb11dd4c9c53922422bde1ea3e385746feebcaca5795331accde88cbe7349c3c4)、部署回调合约 [0x27f80fdc…64db2](https://sepolia.etherscan.io/tx/0x27f80fdcb62044dba220774097afecd491268c42fedf9f4bbbe24c8901864db2)、setRecipient [0xe5befb98…74849](https://lasna.reactscan.net/tx/0xe5befb980b9006d6b7cc87e73465b5ea9cb0bf7aa4d27e1a83cb24d11d874849)、start（订阅 Cron100）[0x806d981f…d9158](https://lasna.reactscan.net/tx/0x806d981f65767e968e67f4efd2ed91bc344c4da2b80395cad73f67f50d4d9158)。

读回：`ticks() = 3`、`active() = false`、`CronReceiver.count() = 3`；之后又过了两个 Cron100 周期（到 Lasna 区块 9024022），ticks 仍是 3，没有第 4 次。

## 怎么防止失控执行

1. **硬上限**：`MAX_TICKS` 在构造时写死（只允许 1–10），第 MAX_TICKS 次 tick 时 `active = false` 并以和订阅完全相同的参数 `unsubscribe`。
2. **双重闸门**：react() 开头检查 `!active || ticks >= MAX_TICKS` 就直接 `return`，就算退订前已排队的 tick 晚到也不会多执行。
3. **构造函数不订阅**：先部署、设好回调地址，再手动 `start()`，避免回调地址还没设好时就开始扣费。
4. **手动刹车**：owner 可随时 `pause()` 退订。
5. **资金上限**：只充值 0.06 lREACT（够 3 次 tick 外加余量）；就算逻辑出错，余额用完产生 debt 后合约也会自动停止。实测 3 次 tick 共花约 0.045 lREACT，剩 0.0146。
6. 只认 Cron 发射地址 `0x…fffFfF` + Cron100 topic；回调合约同时检查 `onlyServiceProvider`（Proxy）和 `onlyCallbackSender`（只认这个 CronTicker）。

## 失败实验：回调 gasLimit 太小

第一版（Lasna [0x3a502352…FF8E](https://lasna.reactscan.net/address/0x3a502352E41123E893c4C931109162705993FF8E)，回调合约 Sepolia [0xf3216D72…DE72](https://sepolia.etherscan.io/address/0xf3216D72e25E3C79ac47B043bE73D3da8EcfDE72)）把回调 gasLimit 设成 200000。3 次 tick 都正常执行、也正常自动停止，但 Sepolia 上 3 笔回调全部失败，例如 [0x6dea0d78…83a99](https://sepolia.etherscan.io/tx/0x6dea0d7801bd004fffbc2da15e064f34c1d0ba444cbee1f56d906aa781883a99)。`cast run` 显示 Callback Proxy 抛出 `InsufficientGas(158925, 200000)`：中继交易的 gas 就等于申请的 gasLimit，扣掉 Proxy 自身开销后不够。改成和营队模板一样的 1,000,000 后（用 `cast call` 先模拟通过），第二版 3 次回调全部成功。测试里加了一条断言锁住 gasLimit = 1,000,000，旧值会让 2 个测试失败。
