// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct FeeInfo {
    address collateral;
    uint256 burnBasisAmount;
    address[] recipients;
    uint256[] basisAmounts;
}