// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

contract TokenMonitor is AbstractReactive {
    error NotOwner();
    error ZeroAddress();
    error ZeroLimit();

    event TransferSeen(address indexed from, address indexed to, uint256 value, uint256 txHash);
    event Exhausted();

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ERC20_TRANSFER_TOPIC_0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    address public immutable OWNER;
    address public immutable TOKEN;

    uint256 public remaining;
    uint256 public seenCount;
    uint256 public turnover;
    uint256 public lastTxHash;
    uint256 public lastReactBlock;

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert NotOwner();
        _;
    }

    constructor(address token_, uint256 limit_) payable {
        if (token_ == address(0)) revert ZeroAddress();
        if (limit_ == 0) revert ZeroLimit();
        OWNER = msg.sender;
        TOKEN = token_;
        remaining = limit_;
        SYSTEM.subscribe(
            SEPOLIA_CHAIN_ID, TOKEN, ERC20_TRANSFER_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    function react(LogRecord calldata log_) external override onlySystem {
        if (
            log_.chainId != SEPOLIA_CHAIN_ID || log_.contractAddress != TOKEN || log_.topic0 != ERC20_TRANSFER_TOPIC_0
                || remaining == 0
        ) return;

        address from = address(uint160(log_.topic1));
        address to = address(uint160(log_.topic2));
        uint256 value = abi.decode(log_.data, (uint256));
        seenCount++;
        turnover += value;
        lastTxHash = log_.txHash;
        lastReactBlock = block.number;
        emit TransferSeen(from, to, value, log_.txHash);

        remaining--;
        if (remaining == 0) _unsubscribe();
    }

    function stop() external onlyOwner {
        if (remaining == 0) return;
        remaining = 0;
        _unsubscribe();
    }

    function _unsubscribe() private {
        SYSTEM.unsubscribe(
            SEPOLIA_CHAIN_ID, TOKEN, ERC20_TRANSFER_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        emit Exhausted();
    }
}
