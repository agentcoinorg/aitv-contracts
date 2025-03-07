// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct LaunchPoolInfo {
    /// @notice Address of the collateral token, 0x0 for native token
    address collateral;
    /// @notice Time window for the launch pool in seconds
    uint256 timeWindow;
    /// @notice Minimum amount of collateral required for launch
    uint256 minAmountForLaunch;
    /// @notice Maximum amount of collateral possible for launch
    uint256 maxAmountForLaunch;
    /// @notice Basis amount of collateral for the uniswap pool
    uint256 collateralUniswapPoolBasisAmount;
    /// @notice Recipients of the collateral
    address[] collateralRecipients;
    /// @notice Basis amounts of the collateral for the recipients
    uint256[] collateralBasisAmounts;
}