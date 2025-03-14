// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {TokenInfo} from "../types/TokenInfo.sol";
import {LaunchPoolInfo} from "../types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "../types/UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "../types/AgentDistributionInfo.sol";

interface IAgentLaunchPool {
    function initialize(
        address _owner, // Owner of the launch pool contract
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        IPoolManager _uniswapPoolManager,
        IPositionManager _uniswapPositionManager
    ) external;

    function computeAgentTokenAddress() external returns(address); // Computes the agent token address before deployment. After deployment, it returns the agent token address
}