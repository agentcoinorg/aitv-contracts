// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct UniswapFeeInfo {
    /// @notice Address of the collateral token
    address collateral;
    /// @notice Basis amount of the agent token for burning
    uint256 burnBasisAmount;
    /// @notice Recipients of the collateral fees
    address[] recipients;
    /// @notice Basis amounts of the collateral fees for the recipients
    uint256[] basisAmounts;
}