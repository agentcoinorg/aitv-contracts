// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAgentToken {
    /// @notice Initializes the agent token contract
    function initialize(string memory name, string memory symbol, address owner, address[] calldata recipients, uint256[] calldata amounts) external;
}