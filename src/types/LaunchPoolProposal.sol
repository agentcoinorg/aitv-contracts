// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TokenInfo} from "./TokenInfo.sol";
import {LaunchPoolInfo} from "./LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "./UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "./AgentDistributionInfo.sol";
import {UniswapFeeInfo} from "./UniswapFeeInfo.sol";

struct LaunchPoolProposal {
    /// @notice Address of the launch pool implementation contract
    address launchPoolImplementation;
    /// @notice Information about the agent token to be created on launch
    TokenInfo tokenInfo;
    /// @notice Information about the launch pool
    LaunchPoolInfo launchPoolInfo;
    /// @notice Information about the uniswap pool deployed after launch
    UniswapPoolInfo uniswapPoolInfo;
    /// @notice Information about the distribution of agent tokens after launch
    AgentDistributionInfo distributionInfo;
    /// @notice Information about the uniswap fee setup for the uniswap pool
    UniswapFeeInfo uniswapFeeInfo;
}