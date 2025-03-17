// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBurnable {
    /// @notice Burns a specific amount of tokens
    function burn(uint256 value) external;
}
