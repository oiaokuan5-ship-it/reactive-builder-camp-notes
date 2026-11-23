# wcb-labs

第 1 周任务 8（ERC-20 转账监控）和任务 9（Cron 定时 + 次数上限）的合约与测试。

- `src/CampToken.sol`：Sepolia 上自己部署的测试代币（CTT）
- `src/TokenMonitor.sol`：Lasna 上的 Reactive 合约，只监听 CTT 的 Transfer，处理 N 次后自动退订
- `src/CronTicker.sol`：Lasna 上的 Reactive 合约，订阅 Cron100，最多触发 MAX_TICKS 次后自动退订
- `src/CronReceiver.sol`：Sepolia 上的回调合约，记录每次定时回调

依赖：`lib/reactive-lib-omni`、`lib/forge-std`（同营队 starter），solc 0.8.29。全部使用 Omni 写法（`SYSTEM.requestCallbackV_1_0`），不用 `emit Callback`。

```bash
forge test   # 24 passed, 0 failed
```
