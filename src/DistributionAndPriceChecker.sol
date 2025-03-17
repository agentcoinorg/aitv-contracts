// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LaunchPoolInfo} from "./types/LaunchPoolInfo.sol";
import {AgentDistributionInfo} from "./types/AgentDistributionInfo.sol";

/// @title DistributionAndPriceChecker
/// @notice The following is a contract to check that all of the collateral and agent tokens are distributed correctly
/// and that the agent token price is higher after launch
abstract contract DistributionAndPriceChecker {
    error PriceLowerAfterLaunch();
    error CollateralMustBeFullyDistributed();
    error AgentTokenMustBeFullyDistributed();

    /// @notice Checks that the collateral and agent tokens are distributed correctly and that the agent token price is higher after launch
    /// @param _launchPoolInfo Launch pool information
    /// @param _distributionInfo Agent distribution information
    function _requireCorrectDistribution(LaunchPoolInfo memory _launchPoolInfo, AgentDistributionInfo memory _distributionInfo) internal virtual pure {
        _requireCollateralFullyDistributed(_launchPoolInfo);
        _requireAgentTokenFullyDistributed(_distributionInfo);
        _requireAgentPriceHigherAfterLaunch(_launchPoolInfo, _distributionInfo);
    }

    /// @notice Checks that the collateral is fully distributed
    /// @param _launchPoolInfo Launch pool information
    function _requireCollateralFullyDistributed(LaunchPoolInfo memory _launchPoolInfo) internal virtual pure {
        uint256 recipientCollateralBasisAmount = 0;

        for (uint256 i = 0; i < _launchPoolInfo.collateralBasisAmounts.length; i++) {
            recipientCollateralBasisAmount += _launchPoolInfo.collateralBasisAmounts[i];
        }

        if (recipientCollateralBasisAmount + _launchPoolInfo.collateralUniswapPoolBasisAmount != 1e4) {
            revert CollateralMustBeFullyDistributed();
        }
    }

    /// @notice Checks that the agent token is fully distributed
    /// @param _distributionInfo Agent distribution information
    function _requireAgentTokenFullyDistributed(AgentDistributionInfo memory _distributionInfo) internal virtual pure {
        uint256 recipientAgentBasisAmount = 0;

        for (uint256 i = 0; i < _distributionInfo.basisAmounts.length; i++) {
            recipientAgentBasisAmount += _distributionInfo.basisAmounts[i];
        }

        if (recipientAgentBasisAmount + _distributionInfo.launchPoolBasisAmount + _distributionInfo.uniswapPoolBasisAmount != 1e4) {
            revert AgentTokenMustBeFullyDistributed();
        }
    }

    /// @notice Checks that the agent token price is higher after launch
    /// @param _launchPoolInfo Launch pool information
    /// @dev The full formula is 'total collateral' : 'launch pool agent tokens' must be lower than 'uniswap pool collateral' : 'uniswap pool agent tokens'
    /// This is to ensure that the depositors of the launch pool bought the agent tokens at a lower price than the initial price on uniswap
    function _requireAgentPriceHigherAfterLaunch(LaunchPoolInfo memory _launchPoolInfo, AgentDistributionInfo memory _distributionInfo) internal virtual pure {
        if (_distributionInfo.uniswapPoolBasisAmount * 1e4 > _launchPoolInfo.collateralUniswapPoolBasisAmount * _distributionInfo.launchPoolBasisAmount) {
            revert PriceLowerAfterLaunch();
        }
    }
}