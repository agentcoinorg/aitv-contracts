// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IFeeSetter} from "./interfaces/IFeeSetter.sol";
import {IAuthorizeLaunchPool} from "./interfaces/IAuthorizeLaunchPool.sol";
import {IAgentLaunchPool} from "./interfaces/IAgentLaunchPool.sol";
import {TokenInfo} from "./types/TokenInfo.sol";
import {LaunchPoolInfo} from "./types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "./types/UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "./types/AgentDistributionInfo.sol";
import {LaunchPoolProposal} from "./types/LaunchPoolProposal.sol";
import {UniswapFeeInfo} from "./types/UniswapFeeInfo.sol";

/// @title AgentFactory
/// @notice The following is a contract to deploy agent launch pools
contract AgentFactory is OwnableUpgradeable, UUPSUpgradeable {
    error OnlyLaunchPool();
    error LengthMismatch();
    error PriceLowerAfterLaunch();

    event Deployed(address launchPool);
    event DeployedProposal(uint256 proposalId, address launchPool);

    IPoolManager public poolManager;
    IPositionManager public positionManager;

    LaunchPoolProposal[] public proposals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _uniswapPoolManager,
        address _positionManager
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        poolManager = IPoolManager(_uniswapPoolManager);
        positionManager = IPositionManager(_positionManager);
    }

    function addProposal(LaunchPoolProposal calldata _proposal) external virtual returns(uint256) {
        if (_proposal.launchPoolInfo.collateralRecipients.length != _proposal.launchPoolInfo.collateralBasisAmounts.length) {
            revert LengthMismatch();
        }

        if (_proposal.distributionInfo.recipients.length != _proposal.distributionInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        if (_proposal.uniswapFeeInfo.recipients.length != _proposal.uniswapFeeInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        _requireAgentPriceHigherAfterLaunch(_proposal.launchPoolInfo, _proposal.distributionInfo);

        proposals.push(_proposal);

        return proposals.length - 1;
    }

    function deployProposal(uint256 proposalId) external virtual onlyOwner returns(address) {
        LaunchPoolProposal memory proposal = proposals[proposalId];

        if (proposal.uniswapFeeInfo.recipients.length != proposal.uniswapFeeInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        address pool = deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );

        emit DeployedProposal(proposalId, pool);

        return pool;
    }

    function deploy(
        address _launchPoolImplementation,
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        UniswapFeeInfo memory _uniswapFeeInfo
    ) public virtual onlyOwner returns(address) {
        if (_launchPoolInfo.collateralRecipients.length != _launchPoolInfo.collateralBasisAmounts.length) {
            revert LengthMismatch();
        }

        if (_distributionInfo.recipients.length != _distributionInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        if (_uniswapFeeInfo.recipients.length != _uniswapFeeInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        _requireAgentPriceHigherAfterLaunch(_launchPoolInfo, _distributionInfo);
      
        ERC1967Proxy proxy = new ERC1967Proxy(
            _launchPoolImplementation, 
            abi.encodeCall(IAgentLaunchPool.initialize, (
                owner(),
                _tokenInfo,
                _launchPoolInfo,
                _uniswapPoolInfo,
                _distributionInfo,
                poolManager,
                positionManager
            ))
        );

        address pool = address(proxy);

        address collateral = _launchPoolInfo.collateral;
        address agentToken = IAgentLaunchPool(pool).computeAgentTokenAddress();

        IFeeSetter(_uniswapPoolInfo.hook).setFeesForPair(collateral, agentToken, _uniswapFeeInfo);
        IAuthorizeLaunchPool(_uniswapPoolInfo.hook).setAuthorizedLaunchPool(pool, true);

        emit Deployed(pool);

        return pool;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function _requireAgentPriceHigherAfterLaunch(LaunchPoolInfo memory _launchPoolInfo, AgentDistributionInfo memory _distributionInfo) internal view {
        if (_distributionInfo.uniswapPoolBasisAmount > _launchPoolInfo.collateralUniswapPoolBasisAmount * _distributionInfo.launchPoolBasisAmount / 1e4) {
            revert PriceLowerAfterLaunch();
        }
    }
}