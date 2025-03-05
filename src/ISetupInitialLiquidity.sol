// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FeeInfo} from "./types/FeeInfo.sol";

interface ISetupInitialLiquidity {
    function setupInitialLiquidity(address _agentTokenAddress, address _collateral, uint256 _agentTokenAmount, uint256 _collateralAmount, FeeInfo memory _feeInfo) external;
}