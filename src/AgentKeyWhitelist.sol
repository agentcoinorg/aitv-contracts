// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract AgentKeyWhitelist {
    function authorizeTransfer(
        address _from,
        address _to,
        uint,
        bool
    ) external pure {
        require(
            _from == address(0) || _to == address(0),
            "TRANSFERS_DISABLED"
        );
    }
}