// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct TokenInfo {
    /// @notice Owner of the token and staking contracts
    address owner;
    /// @notice Name of the token
    string name;
    /// @notice Symbol of the token
    string symbol;
    /// @notice Total supply of the token
    uint256 totalSupply;
    /// @notice Address of the token implementation contract
    address tokenImplementation;
    /// @notice Address of the staking implementation contract
    address stakingImplementation;
}