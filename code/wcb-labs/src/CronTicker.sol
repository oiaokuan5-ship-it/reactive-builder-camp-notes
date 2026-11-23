// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";

contract CronTicker is AbstractReactive {
    error NotOwner();
    error InvalidMaxTicks();
    error ZeroRecipient();
    error AlreadyActive();
    error TickLimitReached();

    event Started();
    event Stopped(uint256 ticks);
    event Tick(uint256 ticks, uint256 rnBlock);

    address public constant CRON_EMITTER = 0x0000000000000000000000000000000000fffFfF;
    uint256 public constant CRON100_TOPIC_0 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;
    uint256 public constant DEST_CHAIN_ID = 11155111;
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;
    address public immutable OWNER;
    uint256 public immutable MAX_TICKS;

    address public recipient;
    bool public active;
    uint256 public ticks;
    uint256 public lastReactBlock;

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    constructor(uint256 maxTicks_) payable {
        if (maxTicks_ == 0 || maxTicks_ > 10) revert InvalidMaxTicks();
        OWNER = msg.sender;
        MAX_TICKS = maxTicks_;
    }

    function setRecipient(address recipient_) external onlyOwner {
        if (active) revert AlreadyActive();
        if (recipient_ == address(0)) revert ZeroRecipient();
        recipient = recipient_;
    }

    function start() external onlyOwner {
        if (active) revert AlreadyActive();
        if (recipient == address(0)) revert ZeroRecipient();
        if (ticks >= MAX_TICKS) revert TickLimitReached();
        active = true;
        SYSTEM.subscribe(
            block.chainid, CRON_EMITTER, CRON100_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        emit Started();
    }

    function pause() external onlyOwner {
        if (active) _stop();
    }

    function react(LogRecord calldata log_) external override onlySystem {
        if (log_.contractAddress != CRON_EMITTER || log_.topic0 != CRON100_TOPIC_0 || !active || ticks >= MAX_TICKS) {
            return;
        }
        ticks++;
        lastReactBlock = block.number;
        emit Tick(ticks, block.number);
        if (ticks == MAX_TICKS) _stop();

        // The callback proxy replaces the first argument with this ticker's address.
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: recipient,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: abi.encodeWithSignature("onCron(address,uint256,uint256)", address(0), ticks, block.number)
            })
        );
    }

    function _stop() private {
        active = false;
        SYSTEM.unsubscribe(
            block.chainid, CRON_EMITTER, CRON100_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        emit Stopped(ticks);
    }
}
