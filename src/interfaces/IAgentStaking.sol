// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAgentStaking {
    /// @notice Initializes the agent staking contract
    function initialize(address owner, address _agentToken) external;
}