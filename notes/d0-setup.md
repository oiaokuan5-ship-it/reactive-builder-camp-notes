# 环境准备：测试钱包、lREACT 和 Foundry

## 测试钱包与余额

我为这次练习单独开了测试钱包，用 Sepolia ETH 换取了 Lasna 上的 lREACT。钱包地址是 `0x08b132d2a647391255B16891c3eD3BFb080Aa307`，可以在浏览器里查看余额和交易记录。[在 Reactscan 查看测试钱包](https://lasna.reactscan.net/address/0x08b132d2a647391255B16891c3eD3BFb080Aa307)

2026-11-20 14:31:46（Asia/Shanghai）查询时，钱包余额为 0.471372299999213723 lREACT。以下是当时的命令和输出。

```bash
cast balance 0x08b132d2a647391255B16891c3eD3BFb080Aa307 --rpc-url https://lasna-rpc.rnk.dev/ -e
```

```text
0.471372299999213723
```

## 学习仓库与 Foundry

学习仓库已经公开，里面记录了「跨链回调三步走」练习的过程。这项练习已提交，目前正在等待审核。[GitHub 学习仓库](https://github.com/oiaokuan5-ship-it/reactive-builder-camp-notes)

本机练习使用 Foundry 1.9.0。提交所需的 `forge --version` 截图要在 David 的电脑上拍摄，待电脑开机后补上。

【截图占位：在 David 电脑上拍摄 `forge --version`，版本应为 Foundry 1.9.0】
