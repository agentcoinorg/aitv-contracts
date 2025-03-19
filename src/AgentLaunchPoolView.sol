// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TokenInfo} from "./types/TokenInfo.sol";
import {LaunchPoolInfo} from "./types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "./types/UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "./types/AgentDistributionInfo.sol";
import {AgentLaunchPool} from "./AgentLaunchPool.sol";

/// @title AgentLaunchPoolView
/// @notice The following is a helper multicall contract for fetching information about agent launch pools
contract AgentLaunchPoolView {
    function info(address payable _agentLaunchPool, address[] calldata _users) external view returns(
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        bool hasLaunched,
        uint256 launchPoolCreatedOn,
        uint256 totalDeposited,
        address agentToken,
        address agentStaking,
        uint256[] memory userDeposits
    ) {
        AgentLaunchPool pool = AgentLaunchPool(_agentLaunchPool);
    
        _tokenInfo = pool.getTokenInfo();
        _launchPoolInfo = pool.getLaunchPoolInfo();
        _uniswapPoolInfo = pool.getUniswapPoolInfo();
        _distributionInfo = pool.getDistributionInfo();

        hasLaunched = pool.hasLaunched();
        launchPoolCreatedOn = pool.launchPoolCreatedOn();
        totalDeposited = pool.totalDeposited();
        agentToken = pool.computeAgentTokenAddress();
        agentStaking = pool.agentStaking();

        userDeposits = new uint256[](_users.length);
        for (uint256 i = 0; i < _users.length; i++) {
            userDeposits[i] = pool.deposits(_users[i]);
        }
    }
}