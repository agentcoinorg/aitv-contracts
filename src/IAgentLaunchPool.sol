// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';

import {FeeInfo} from "./types/FeeInfo.sol";

interface IAgentLaunchPool {
    struct TokenInfo {
        address owner;
        string name;
        string symbol;
        uint256 totalSupply;
        address tokenImplementation;
        address stakingImplementation;
    }

    struct LaunchPoolInfo {
        address collateral;
        uint256 timeWindow;
        uint256 minAmountForLaunch;
        uint256 maxAmountForLaunch;
    }

    struct DistributionInfo {
        address[] recipients;
        uint256[] basisAmounts;
        uint256 launchPoolBasisAmount;
        uint256 uniswapPoolBasisAmount;
    }

    function initialize(
        address _owner,
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        DistributionInfo memory _distributionInfo,
        IPositionManager _uniswapPositionManager
    ) external;

    function computeAgentTokenAddress() external returns(address);
}