// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

import {CampToken} from "../src/CampToken.sol";
import {TokenMonitor} from "../src/TokenMonitor.sol";
import {CronTicker} from "../src/CronTicker.sol";
import {CronReceiver} from "../src/CronReceiver.sol";

contract MockSystem {
    bytes[] public subscriptions;
    bytes[] public unsubscriptions;
    ISystemContract.CallbackConfiguration_V_1_0[] private requests;

    // Keep the complete six-argument tuple for exact comparisons in the tests.
    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscriptions.push(msg.data[4:]);
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        unsubscriptions.push(msg.data[4:]);
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 calldata request) external {
        requests.push(request);
    }

    function subscriptionCount() external view returns (uint256) {
        return subscriptions.length;
    }

    function unsubscriptionCount() external view returns (uint256) {
        return unsubscriptions.length;
    }

    function requestCount() external view returns (uint256) {
        return requests.length;
    }

    function requestAt(uint256 index) external view returns (ISystemContract.CallbackConfiguration_V_1_0 memory) {
        return requests[index];
    }
}

abstract contract ReactiveFixture is Test {
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    uint256 internal constant SEPOLIA = 11155111;
    uint256 internal constant IGNORE_TOPIC = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    MockSystem internal constant system = MockSystem(SYSTEM);

    function setUp() public virtual {
        vm.chainId(5318007);
        vm.etch(SYSTEM, type(MockSystem).runtimeCode);
    }

    function subscription(uint256 chainId, address emitter, uint256 topic0) internal pure returns (bytes memory) {
        return abi.encode(chainId, emitter, topic0, IGNORE_TOPIC, IGNORE_TOPIC, IGNORE_TOPIC);
    }
}

contract CampTokenTest is Test {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function testMintEmitsTransferAndSetsSupply() public {
        vm.expectEmit(true, true, false, true);
        emit CampToken.Transfer(address(0), address(this), 100);
        CampToken token = new CampToken(100);

        assertEq(token.name(), "Camp Test Token");
        assertEq(token.symbol(), "CTT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 100);
        assertEq(token.balanceOf(address(this)), 100);
    }

    function testTransferEmitsEventAndMovesBalance() public {
        CampToken token = new CampToken(100);
        vm.expectEmit(address(token));
        emit CampToken.Transfer(address(this), ALICE, 30);
        assertTrue(token.transfer(ALICE, 30));
        assertEq(token.balanceOf(address(this)), 70);
        assertEq(token.balanceOf(ALICE), 30);
        assertEq(token.totalSupply(), 100);
    }

    function testApprovedSpenderCanOnlyUseRemainingAllowance() public {
        CampToken token = new CampToken(100);
        assertTrue(token.approve(ALICE, 40));
        assertEq(token.allowance(address(this), ALICE), 40);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 25));
        assertEq(token.allowance(address(this), ALICE), 15);

        vm.expectRevert();
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 16);
        assertEq(token.balanceOf(address(this)), 75);
        assertEq(token.balanceOf(BOB), 25);
        assertEq(token.allowance(address(this), ALICE), 15);
    }
}

contract TokenMonitorTest is ReactiveFixture {
    address internal constant TOKEN = address(0xC77);
    address internal constant FROM = address(0xA11CE);
    address internal constant TO = address(0xB0B);
    uint256 internal constant TRANSFER_TOPIC = uint256(keccak256("Transfer(address,address,uint256)"));
    TokenMonitor internal monitor;

    function setUp() public override {
        super.setUp();
        monitor = new TokenMonitor(TOKEN, 2);
    }

    function transferLog(uint256 value, uint256 txHash) internal pure returns (IReactive.LogRecord memory entry) {
        entry.chainId = SEPOLIA;
        entry.contractAddress = TOKEN;
        entry.topic0 = TRANSFER_TOPIC;
        entry.topic1 = uint160(FROM);
        entry.topic2 = uint160(TO);
        entry.data = abi.encode(value);
        entry.txHash = txHash;
        entry.blockNumber = 91;
    }

    function deliver(IReactive.LogRecord memory entry) internal {
        vm.prank(SYSTEM);
        monitor.react(entry);
    }

    function testConstructorSubscribesToSepoliaTokenTransfers() public view {
        assertEq(monitor.OWNER(), address(this));
        assertEq(monitor.TOKEN(), TOKEN);
        assertEq(monitor.remaining(), 2);
        assertEq(system.subscriptionCount(), 1);
        assertEq(system.subscriptions(0), subscription(SEPOLIA, TOKEN, TRANSFER_TOPIC));
    }

    function testConstructorRejectsZeroTokenOrLimit() public {
        vm.expectRevert();
        new TokenMonitor(address(0), 2);
        vm.expectRevert();
        new TokenMonitor(TOKEN, 0);
        assertEq(system.subscriptionCount(), 1);
    }

    function testOnlySystemCanDeliverTransfer() public {
        vm.expectRevert();
        monitor.react(transferLog(4, 1));
    }

    function testUnrelatedLogsAreIgnoredBeforeDecoding() public {
        IReactive.LogRecord memory entry = transferLog(4, 1);
        entry.data = bytes("");
        vm.recordLogs();

        entry.chainId = 1;
        deliver(entry);
        entry.chainId = SEPOLIA;
        entry.contractAddress = TO;
        deliver(entry);
        entry.contractAddress = TOKEN;
        entry.topic0 = 0;
        deliver(entry);

        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(monitor.remaining(), 2);
        assertEq(monitor.seenCount(), 0);
        assertEq(monitor.turnover(), 0);
        assertEq(monitor.lastTxHash(), 0);
        assertEq(monitor.lastReactBlock(), 0);
        assertEq(system.unsubscriptionCount(), 0);
        assertEq(system.requestCount(), 0);
    }

    function testDecodesTransferAndStopsExactlyAtLimit() public {
        vm.roll(300);
        vm.expectEmit(address(monitor));
        emit TokenMonitor.TransferSeen(FROM, TO, 17, 0xABC);
        deliver(transferLog(17, 0xABC));
        assertEq(monitor.seenCount(), 1);
        assertEq(monitor.remaining(), 1);
        assertEq(monitor.turnover(), 17);
        assertEq(monitor.lastTxHash(), 0xABC);
        assertEq(monitor.lastReactBlock(), 300);
        assertEq(system.unsubscriptionCount(), 0);

        vm.roll(301);
        vm.expectEmit(address(monitor));
        emit TokenMonitor.TransferSeen(FROM, TO, 9, 0xDEF);
        vm.expectEmit(address(monitor));
        emit TokenMonitor.Exhausted();
        deliver(transferLog(9, 0xDEF));
        assertEq(system.unsubscriptionCount(), 1);
        assertEq(system.unsubscriptions(0), system.subscriptions(0));

        vm.roll(302);
        vm.recordLogs();
        deliver(transferLog(100, 0xCAB));
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(monitor.seenCount(), 2);
        assertEq(monitor.remaining(), 0);
        assertEq(monitor.turnover(), 26);
        assertEq(monitor.lastTxHash(), 0xDEF);
        assertEq(monitor.lastReactBlock(), 301);
        assertEq(system.unsubscriptionCount(), 1);
        assertEq(system.requestCount(), 0);
    }

    function testOnlyOwnerCanStop() public {
        vm.expectRevert();
        vm.prank(TO);
        monitor.stop();
        assertEq(monitor.remaining(), 2);
        assertEq(system.unsubscriptionCount(), 0);
    }

    function testStopUnsubscribesOnceAndPreservesHistory() public {
        deliver(transferLog(7, 42));
        vm.expectEmit(address(monitor));
        emit TokenMonitor.Exhausted();
        monitor.stop();
        assertEq(monitor.remaining(), 0);
        assertEq(system.unsubscriptionCount(), 1);
        assertEq(system.unsubscriptions(0), system.subscriptions(0));

        vm.recordLogs();
        monitor.stop();
        deliver(transferLog(8, 43));
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(monitor.seenCount(), 1);
        assertEq(monitor.turnover(), 7);
        assertEq(system.unsubscriptionCount(), 1);
        assertEq(system.requestCount(), 0);
    }
}

contract CronTickerTest is ReactiveFixture {
    address internal constant EMITTER = 0x0000000000000000000000000000000000fffFfF;
    uint256 internal constant CRON100_TOPIC_0 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    address internal constant RECIPIENT = address(0xC77);
    address internal constant OTHER = address(0xA11CE);
    CronTicker internal ticker;

    function setUp() public override {
        super.setUp();
        ticker = new CronTicker(3);
    }

    function cronLog() internal view returns (IReactive.LogRecord memory entry) {
        entry.chainId = block.chainid;
        entry.contractAddress = EMITTER;
        entry.topic0 = CRON100_TOPIC_0;
    }

    function deliver(IReactive.LogRecord memory entry) internal {
        vm.prank(SYSTEM);
        ticker.react(entry);
    }

    function startTicker() internal {
        ticker.setRecipient(RECIPIENT);
        ticker.start();
    }

    function assertRequest(uint256 index, address recipient, uint256 tick, uint256 rnBlock) internal view {
        ISystemContract.CallbackConfiguration_V_1_0 memory request = system.requestAt(index);
        assertEq(request.chainId, SEPOLIA);
        assertEq(request.recipient, recipient);
        assertEq(request.gasLimit, 1_000_000, "Sepolia proxy reverts InsufficientGas when callback gasLimit is 200k (seen 2026-11-23)");
        assertEq(request.payload, abi.encodeCall(CronReceiver.onCron, (address(0), tick, rnBlock)));
    }

    function testConstructorLeavesTickerInactiveAndUnsubscribed() public view {
        assertEq(ticker.OWNER(), address(this));
        assertEq(ticker.MAX_TICKS(), 3);
        assertFalse(ticker.active());
        assertEq(system.subscriptionCount(), 0);
    }

    function testMaxTicksRangeIsOneThroughTen() public {
        vm.expectRevert();
        new CronTicker(0);
        vm.expectRevert();
        new CronTicker(11);
        assertEq((new CronTicker(1)).MAX_TICKS(), 1);
        assertEq((new CronTicker(10)).MAX_TICKS(), 10);
    }

    function testTickBeforeStartDoesNothing() public {
        vm.recordLogs();
        deliver(cronLog());
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(ticker.ticks(), 0);
        assertEq(ticker.lastReactBlock(), 0);
        assertEq(system.requestCount(), 0);
        assertEq(system.unsubscriptionCount(), 0);
    }

    function testStartSubscribesToCronOnCurrentChain() public {
        // An alternate local chain ID detects accidental hardcoding of Lasna.
        vm.chainId(31337);
        ticker.setRecipient(RECIPIENT);
        vm.expectEmit(address(ticker));
        emit CronTicker.Started();
        ticker.start();
        assertTrue(ticker.active());
        assertEq(system.subscriptionCount(), 1);
        assertEq(system.subscriptions(0), subscription(31337, EMITTER, CRON100_TOPIC_0));
    }

    function testStartAndRecipientGuards() public {
        vm.expectRevert();
        ticker.start();
        vm.expectRevert();
        ticker.setRecipient(address(0));

        startTicker();
        vm.expectRevert();
        ticker.start();
        vm.expectRevert();
        ticker.setRecipient(OTHER);
        assertEq(ticker.recipient(), RECIPIENT);
        assertEq(system.subscriptionCount(), 1);
    }

    function testOnlyOwnerCanSetRecipientStartOrPause() public {
        vm.expectRevert();
        vm.prank(OTHER);
        ticker.setRecipient(RECIPIENT);

        ticker.setRecipient(RECIPIENT);
        vm.expectRevert();
        vm.prank(OTHER);
        ticker.start();

        ticker.start();
        vm.expectRevert();
        vm.prank(OTHER);
        ticker.pause();
        assertTrue(ticker.active());
        assertEq(system.unsubscriptionCount(), 0);
    }

    function testOnlySystemCanDeliverTick() public {
        startTicker();
        vm.expectRevert();
        ticker.react(cronLog());
    }

    function testWrongEmitterOrTopicIsIgnoredWhileActive() public {
        startTicker();
        IReactive.LogRecord memory entry = cronLog();
        vm.recordLogs();
        entry.contractAddress = OTHER;
        deliver(entry);
        entry.contractAddress = EMITTER;
        entry.topic0 = 0;
        deliver(entry);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(ticker.ticks(), 0);
        assertEq(ticker.lastReactBlock(), 0);
        assertEq(system.requestCount(), 0);
        assertEq(system.unsubscriptionCount(), 0);
        assertTrue(ticker.active());
    }

    function testThreeTicksRequestThreeCallbacksIncludingFinalTick() public {
        startTicker();
        for (uint256 tick = 1; tick <= 3; ++tick) {
            uint256 rnBlock = 900 + tick;
            vm.roll(rnBlock);
            vm.expectEmit(address(ticker));
            emit CronTicker.Tick(tick, rnBlock);
            if (tick == 3) {
                vm.expectEmit(address(ticker));
                emit CronTicker.Stopped(3);
            }
            deliver(cronLog());
            assertEq(ticker.ticks(), tick);
            assertEq(ticker.lastReactBlock(), rnBlock);
            assertEq(system.requestCount(), tick);
            assertRequest(tick - 1, RECIPIENT, tick, rnBlock);
            assertEq(ticker.active(), tick < 3);
            assertEq(system.unsubscriptionCount(), tick == 3 ? 1 : 0);
        }
        assertEq(system.unsubscriptions(0), system.subscriptions(0));

        vm.roll(904);
        vm.recordLogs();
        deliver(cronLog());
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(ticker.ticks(), 3);
        assertEq(ticker.lastReactBlock(), 903);
        assertEq(system.requestCount(), 3);
        assertEq(system.unsubscriptionCount(), 1);
        vm.expectRevert();
        ticker.start();
    }

    function testPauseAndResumePreserveTicksAndAllowRecipientChange() public {
        startTicker();
        vm.roll(70);
        deliver(cronLog());
        vm.expectEmit(address(ticker));
        emit CronTicker.Stopped(1);
        ticker.pause();
        assertFalse(ticker.active());
        assertEq(system.unsubscriptionCount(), 1);
        assertEq(system.unsubscriptions(0), system.subscriptions(0));

        vm.roll(71);
        deliver(cronLog());
        assertEq(ticker.ticks(), 1);
        assertEq(ticker.lastReactBlock(), 70);
        assertEq(system.requestCount(), 1);

        ticker.setRecipient(OTHER);
        ticker.start();
        assertEq(system.subscriptionCount(), 2);
        assertEq(system.subscriptions(1), system.subscriptions(0));
        vm.roll(72);
        deliver(cronLog());
        assertEq(ticker.ticks(), 2);
        assertEq(system.requestCount(), 2);
        assertRequest(1, OTHER, 2, 72);
    }
}

contract CronReceiverTest is Test {
    address internal constant PROXY = address(0xC01);
    address internal constant REACTIVE = address(0xC02);
    CronReceiver internal receiver;

    function setUp() public {
        receiver = new CronReceiver(PROXY, REACTIVE);
    }

    function testDirectCallWithCorrectSenderReverts() public {
        vm.expectRevert();
        receiver.onCron(REACTIVE, 1, 900);
        assertEq(receiver.count(), 0);
    }

    function testProxyCallWithWrongSenderReverts() public {
        vm.expectRevert();
        vm.prank(PROXY);
        receiver.onCron(address(0xBAD), 1, 900);
        assertEq(receiver.count(), 0);
    }

    function testAuthorizedCallbacksRecordTickAndLocalTime() public {
        vm.warp(5000);
        vm.expectEmit(address(receiver));
        emit CronReceiver.CronHandled(7, 900, 5000);
        vm.prank(PROXY);
        receiver.onCron(REACTIVE, 7, 900);
        assertEq(receiver.count(), 1);
        assertEq(receiver.lastTick(), 7);

        vm.prank(PROXY);
        receiver.onCron(REACTIVE, 8, 901);
        assertEq(receiver.count(), 2);
        assertEq(receiver.lastTick(), 8);
    }

    function testReceiverAcceptsEther() public {
        vm.deal(address(this), 2 ether);
        CronReceiver funded = new CronReceiver{value: 1 ether}(PROXY, REACTIVE);
        (bool ok,) = address(funded).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(funded).balance, 2 ether);
    }
}
