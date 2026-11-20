# 项目方向卡（草稿）：测试网 Morpho Blue 仓位自救

这是一份按任务要求整理的草稿，待对照 WCB 题面微调。本机 `forge test` 已通过 17/17 项测试，项目尚未部署到任何测试网。

## 要解决的问题和服务的用户

抵押品价格下跌时，Morpho Blue 仓位的贷款价值比（LTV）会上升。等仓位所有者看到风险、准备稳定币并手动还债，可能已经发生清算。此时再还债，也拿不回已被清算的抵押品。

这个黑客松原型供仓位所有者在测试网上演示自救。演示只涉及一个市场、一个借款人和一种还债动作，目的是在清算前降低负债，不提供完整的借贷服务或收益策略。David 没有实盘借款，本项目不构成投资建议。

## 触发事件、反应逻辑和回调动作

1. **Lasna 的定时触发。** `MorphoRescueReactive` 监听 Lasna（chainId 5318007）的 `Cron100(uint256)`。该事件约每 100 个区块出现一次，间隔约 2 分钟。每次收到这个事件，`react()` 都调用 `SYSTEM.requestCallbackV_1_0` 请求回调。Lasna 合约不读取 Morpho 仓位，也不判断 LTV。
2. **Base Sepolia 的检查和还债。** 目的链设计为 Base Sepolia（chainId 84532）。Callback Proxy 将请求送达 `MorphoRescueCallback` 后，回调合约先调用 `accrueInterest` 累计利息，再读取 Morpho 的市场、借款人仓位和 oracle 报价，计算 LTV。低于警戒线时无需还债。达到警戒线且仍低于清算线（`warning <= LTV < LLTV`）时，合约用预存的稳定币部分还债，目标是把 LTV 降到目标线。若 `LTV >= LLTV`，合约只记录跳过。
3. **检查完成后记账。** Lasna 合约也订阅目的链回调合约发出的 `Checked`。收到该事件时只增加 `completedChecks`，不会请求新的回调。下一次检查由下一次 Cron100 触发。

## 风险控制

- **救援资金有限。** 回调合约只能动用自己的预存稳定币，不会从借款人的钱包扣款。它只向固定的 Morpho 合约授权本次还债所需的额度，调用 `repay` 后清除 `allowance`。原型没有提款入口。备付不足时只能按现有资金还债，仓位可能仍高于目标线。
- **救援资金和手续费要分别准备。** 即使当轮没有还债，执行 Cron 检查也会收费，因此需要能暂停定时订阅。Lasna 的 Reactive 合约和目的链回调分别需要支付费用。若产生 `debt > 0`，相应链上的事件或回调投递就会停摆。可向该链的 SYSTEM 或 Callback Proxy 调用 `depositTo(address)`，指定对应合约，先清欠费，再补充预付额度。
- **定时检查有间隔。** 回调执行失败会回滚，只能等下一次 Cron100 再试。即使上一次检查时仓位还安全，也可能在下一次回调送达前就发生清算，无法保证来得及自救。

## 仍未决定的事项与提交材料

- 具体使用哪个 Base Sepolia Morpho 市场，还要上链核对市场的五个参数。警戒 LTV、目标 LTV 和备付资金规模也尚未确定。部署与广播均待 David 确认。
- 赛道尚未选定。约 2 分钟一次的定时检查更接近「Set It and Forget It」，而 Base Sepolia 作为目的链也符合「Every Second Counts」的链要求。
- David 尚未报名 DoraHacks，需要在 11/21 前亲自报名。提交方向卡还缺报名截图或 BUIDL 链接。[DoraHacks 报名页](https://dorahacks.io/hackathon/reactive-omni-buildathon/detail)
