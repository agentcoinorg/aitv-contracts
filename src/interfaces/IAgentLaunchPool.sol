// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';

import {FeeInfo} from "../types/FeeInfo.sol";

interface IAgentLaunchPool {
    struct TokenInfo {
        address owner; // Owner of the token and staking contracts
        string name; // Name of the token
        string symbol; // Symbol of the token
        uint256 totalSupply; // Total supply of the token
        address tokenImplementation; // Address of the token implementation contract
        address stakingImplementation; // Address of the staking implementation contract
    }

    struct LaunchPoolInfo {
        address collateral; // Address of the collateral token, 0x0 for native token
        uint256 timeWindow; // Time window for the launch pool in seconds
        uint256 minAmountForLaunch; // Minimum amount of collateral required for launch
        uint256 maxAmountForLaunch; // Maximum amount of collateral possible for launch
        uint256 collateralUniswapPoolBasisAmount; // Basis amount of collateral for the uniswap pool
        address[] collateralRecipients; // Recipients of the collateral
        uint256[] collateralBasisAmounts; // Basis amounts of the collateral for the recipients
    }

    struct UniswapPoolInfo {
        address lpRecipient; // Recipient of the LP ERC721 token
        uint24 lpFee; // Fee for the LP
        int24 tickSpacing; // Tick spacing for the uniswap pool
        uint160 startingPrice; // Starting price for the uniswap pool
    }

    struct AgentDistributionInfo {
        address[] recipients; // Recipients of the agent token airdrop
        uint256[] basisAmounts; // Basis amounts of the agent token airdrop for the recipients
        uint256 launchPoolBasisAmount; // Basis amount of the agent token for the launch pool
        uint256 uniswapPoolBasisAmount; // Basis amount of the agent token for the uniswap pool
    }

    function initialize(
        address _owner, // Owner of the launch pool contract
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        IPositionManager _uniswapPositionManager
    ) external;

    function computeAgentTokenAddress() external returns(address); // Computes the agent token address before deployment. After deployment, it returns the agent token address
}