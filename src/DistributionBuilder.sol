// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Action, ActionType} from "../src/TokenDistributor.sol";

contract DistributionBuilder {
    Action[] internal rawActions;

    function build() external view returns (Action[] memory) {
        return rawActions;
    }

    function burn(
        uint256 basisPoints
    ) external returns (DistributionBuilder) {
        rawActions.push(Action({
            actionType: ActionType.Burn,
            basisPoints: uint16(basisPoints),
            recipient: address(0),
            token: address(0),
            distributionId: 0,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        }));

        return this;
    }

    function send(
        uint256 basisPoints,
        address recipient
    ) external returns (DistributionBuilder) {
        rawActions.push(Action({
            actionType: ActionType.Send,
            basisPoints: uint16(basisPoints),
            recipient: recipient,
            token: address(0),
            distributionId: 0,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        }));

        return this;
    }

    function buy(
        uint256 _basisPoints,
        address _tokenToBuy,
        uint256 _distributionId
    ) external returns (DistributionBuilder) {
        rawActions.push(Action({
            actionType: ActionType.Buy,
            basisPoints: uint16(_basisPoints),
            token: _tokenToBuy,
            distributionId: uint32(_distributionId),
            recipient: address(0),
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        }));

        return this;
    }

    function buy(
        uint256 _basisPoints,
        address _tokenToBuy,
        address _recipient
    ) external returns (DistributionBuilder) {
        rawActions.push(Action({
            actionType: ActionType.Buy,
            basisPoints: uint16(_basisPoints),
            token: _tokenToBuy,
            distributionId: 0,
            recipient: _recipient,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        }));

        return this;
    }

    function sendAndCall(
        uint256 _basisPoints,
        address recipient,
        bytes4 selector,
        bytes12 callArgsPacked
    ) external returns (DistributionBuilder) {
        rawActions.push(Action({
            actionType: ActionType.SendAndCall,
            basisPoints: uint16(_basisPoints),
            recipient: recipient,
            selector: selector,
            token: address(0),
            distributionId: 0,
            callArgsPacked: callArgsPacked
        }));

        return this;
    }

    function sendAndCall(
        uint256 _basisPoints,
        address recipient,
        bytes4 selector
    ) external returns (DistributionBuilder) {
        rawActions.push(Action({
            actionType: ActionType.SendAndCall,
            basisPoints: uint16(_basisPoints),
            recipient: recipient,
            selector: selector,
            token: address(0),
            distributionId: 0,
            callArgsPacked: bytes12(0)
        }));

        return this;
    }
}