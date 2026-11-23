// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AbstractCallback} from "@reactive/src/base/AbstractCallback.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";

contract CronReceiver is AbstractCallback {
    event CronHandled(uint256 tick, uint256 rnBlock, uint256 timestamp);

    uint256 public count;
    uint256 public lastTick;

    constructor(address callbackProxy_, address reactive_)
        payable
        AbstractCallback(IPayable(payable(callbackProxy_)), reactive_)
    {}

    function onCron(address sender_, uint256 tick_, uint256 rnBlock_)
        external
        onlyServiceProvider
        onlyCallbackSender(sender_)
    {
        count++;
        lastTick = tick_;
        emit CronHandled(tick_, rnBlock_, block.timestamp);
    }
}
