# 读懂 Lasna 上的 Reactive 合约费用

2026-11-20 14:31:39–14:31:46（Asia/Shanghai，CST），我通过 Lasna RPC `https://lasna-rpc.rnk.dev/` 读取了系统合约 SYSTEM（`0x8888888888888888888888888888888888888888`）的三个参数。

**计价系数**

```bash
cast call 0x8888888888888888888888888888888888888888 "_gasPriceCoeffPer1000()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
```

```
1000
```

**每次执行的固定附加 gas**

```bash
cast call 0x8888888888888888888888888888888888888888 "_extraGas()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
```

```
100000 [1e5]
```

**调用付款函数时可用的 gas 上限**

```bash
cast call 0x8888888888888888888888888888888888888888 "_maxChargeGas()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
```

```
50000 [5e4]
```

## 一次 `react()` 的费用怎么算？

官方公式是 `fee = p_base × C × (g_used + K)`。先把本次实际消耗的 gas（`g_used`）与固定附加量相加，再乘以基础 gas 价格和计价系数。[Reactive Network 官方费用文档](https://dev.reactive.network/economy)

- `p_base` 取这笔交易的 `tx.gasprice` 与所在区块的 `block.basefee` 中较大的值。
- `C = _gasPriceCoeffPer1000 / 1000`。本次读取到 1000，换算后 `C = 1`。
- `K = _extraGas`，本次读取到 100000 gas。另一个读数 `_maxChargeGas` 为 50000 gas，只限制结算时调用 `pay()` 可用的 gas，不进入费用公式。

2026-11-20 14:33:18（Asia/Shanghai），我又查询了 Lasna 的 gas 价格和最新区块的基础费。两项读数都折合 100 gwei。

```bash
cast gas-price --rpc-url https://lasna-rpc.rnk.dev/
```

```
100000000000
```

```bash
cast block latest --rpc-url https://lasna-rpc.rnk.dev/ --field baseFeePerGas
```

```
100000000000
```

按 100 gwei 举例，**假设**某次 `react()` 的 `g_used` 为 50,000 gas，费用就是 `100 gwei × 1 × (50,000 + 100,000) = 0.015 lREACT`。50,000 是演算用的假设值，这里没有测量某笔交易的 gas 消耗。

## balance、reserves、debt 分别是什么？为什么只要有一点 debt，合约就停止执行？

| 项目 | 资金或账目在哪里 | 含义 |
| --- | --- | --- |
| `balance` | 合约自己的地址 | 合约可自行支配的余额，也可以用来支付手续费。 |
| `reserves` | Lasna 上的 SYSTEM 或目的链上的 Callback Proxy | 为某个合约预存的额度，只能支付手续费。 |
| `debt` | Lasna 上的 SYSTEM 或目的链上的 Callback Proxy | 该合约已经产生、尚未付清的费用。 |

结算时先扣 `reserves`，不足的部分记为 `debt`。SYSTEM 或目的链的 Callback Proxy 可以在同一笔交易中调用合约的 `pay()`，用合约自己的余额结清欠费。如果通过 `depositTo(address)` 为指定合约充值，存款会先清偿该合约的 `debt`，剩余部分才记入 `reserves`。因此，同一个合约在同一本账上不会同时有预付额度和欠费。

**直接给合约转币只会增加 balance，既不清偿 debt，也不形成 reserves。** 课程速查表把直接转币和调用 `coverDebt()` 都列为处理欠费的办法，这里还要看合约接口。官方 Omni 模板中的 `_coverDebt()` 是 `internal` 函数，默认没有对外的 `coverDebt()`。要为指定合约清偿欠费，直接在对应的 SYSTEM 或 Callback Proxy 上调用 `depositTo(address)` 最稳妥。

SYSTEM 会在为下一次 `react()` 花费任何 gas 之前检查欠费。只要账上还有 `debt > 0`，SYSTEM 就不再调用该合约的 `react()`，合约进入 `inactive` 状态。目的链也会检查回调合约在 Callback Proxy 的欠费，有欠费就停止投递回调。因为检查发生在执行之前，现象是合约静默停摆。

2026-11-20 14:31:46（Asia/Shanghai），我查询了 CampReactive 练习合约 `0x847C65ad7B08Ce4b885FA97244dCBCDDdf7Beb2f` 的余额和账目。Morpho 自救项目尚未部署。

```bash
cast balance 0x847C65ad7B08Ce4b885FA97244dCBCDDdf7Beb2f --rpc-url https://lasna-rpc.rnk.dev/ -e
```

```
0.481873800000000000
```

```bash
cast call 0x8888888888888888888888888888888888888888 "debt(address)(uint256)" 0x847C65ad7B08Ce4b885FA97244dCBCDDdf7Beb2f --rpc-url https://lasna-rpc.rnk.dev/
```

```
0
```

```bash
cast call 0x8888888888888888888888888888888888888888 "reserves(address)(uint256)" 0x847C65ad7B08Ce4b885FA97244dCBCDDdf7Beb2f --rpc-url https://lasna-rpc.rnk.dev/
```

```
0
```

当时合约自己还持有约 0.4819 lREACT，SYSTEM 记录的欠费和预付额度都为零。这与练习中对费用的解读一致，即此前通过 `pay()` 从合约的 `balance` 付款，无需动用 `reserves`。这组三个读数只能确认查询时的状态，单凭它们无法还原每笔历史付款。

## `react()` 执行回滚了，还收费吗？这对合约设计意味着什么？

还收费。SYSTEM 捕获 `revert` 后记录 `ReactiveContractReverted`，仍按实际消耗的 gas 套用公式收取全额费用，不会退款。目的链回调执行失败时，Callback Proxy 记录 `CallbackFailure`，同样全额收费。唯一例外是回调目标账户没有代码，Proxy 会在收费前拒绝投递。

遇到无需处理的事件时，应尽早用 `return` 正常退出。已经消耗的 gas 仍要付费，改用 `revert` 也省不下这笔钱。每次 Cron 触发执行都会收费，即使本轮无需还债也一样，因此要保留暂停或退订的办法，否则反复执行可能耗尽资金，留下欠费后合约就会停摆。

回调请求的 `gasLimit` 至少为 100,000 gas（100k）。估算时还要为目的链 Proxy 预留记账所需的 `_extraGas` 和结算所需的 `_maxChargeGas`，余下的 gas 才能用于目标合约。两项预留量以目的链 Proxy 自身的参数为准。
