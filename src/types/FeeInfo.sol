// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct FeeInfo {
    address collateral; // Address of the collateral token
    uint256 burnBasisAmount; // Basis amount of the agent token for burning
    address[] recipients; // Recipients of the collateral fees
    uint256[] basisAmounts; // Basis amounts of the collateral fees for the recipients
}