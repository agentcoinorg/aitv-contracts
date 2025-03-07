// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AgentDistributionInfo {
    /// @notice Recipients of the agent token airdrop
    address[] recipients;
    /// @notice Basis amounts of the agent token airdrop for the recipients
    uint256[] basisAmounts;
    /// @notice Basis amount of the agent token for the launch pool
    uint256 launchPoolBasisAmount;
    /// @notice Basis amount of the agent token for the uniswap pool
    uint256 uniswapPoolBasisAmount;
}