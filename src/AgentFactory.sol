// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IFeeSetter, UniswapFeeInfo} from "./interfaces/IFeeSetter.sol";
import {
    IAgentLaunchPool, 
    TokenInfo,
    LaunchPoolInfo,
    UniswapPoolInfo,
    AgentDistributionInfo 
} from "./interfaces/IAgentLaunchPool.sol";

/// @title AgentFactory
/// @notice The following is a contract to deploy agent launch pools
contract AgentFactory is OwnableUpgradeable, UUPSUpgradeable {
    error OnlyLaunchPool();

    event Deployed(address launchPool);
    event DeployedProposal(uint256 proposalId, address launchPool);

    IPositionManager public positionManager;

    struct DeploymentProposal {
        address launchPoolImplementation;
        TokenInfo tokenInfo;
        LaunchPoolInfo launchPoolInfo;
        UniswapPoolInfo uniswapPoolInfo;
        AgentDistributionInfo distributionInfo;
        UniswapFeeInfo uniswapFeeInfo;
    }

    DeploymentProposal[] public proposals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _uniswapPositionManager
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        positionManager = IPositionManager(_uniswapPositionManager);
    }

    function addProposal(
        address _launchPoolImplementation,
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        UniswapFeeInfo memory _uniswapFeeInfo
    ) external returns(uint256) {
        DeploymentProposal memory proposal = DeploymentProposal({
            launchPoolImplementation: _launchPoolImplementation,
            tokenInfo: _tokenInfo,
            launchPoolInfo: _launchPoolInfo,
            uniswapPoolInfo: _uniswapPoolInfo,
            distributionInfo: _distributionInfo,
            uniswapFeeInfo: _uniswapFeeInfo
        });

        proposals.push(proposal);

        return proposals.length - 1;
    }

    function deployProposal(uint256 proposalId) external virtual onlyOwner returns(address) {
        DeploymentProposal memory proposal = proposals[proposalId];

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
        ERC1967Proxy proxy = new ERC1967Proxy(
            _launchPoolImplementation, 
            abi.encodeCall(IAgentLaunchPool.initialize, (
                owner(),
                _tokenInfo,
                _launchPoolInfo,
                _uniswapPoolInfo,
                _distributionInfo,
                positionManager
            ))
        );

        address pool = address(proxy);

        address collateral = _launchPoolInfo.collateral;
        address agentToken = IAgentLaunchPool(pool).computeAgentTokenAddress();

        IFeeSetter(_uniswapPoolInfo.hook).setFeesForPair(collateral, agentToken, _uniswapFeeInfo);

        emit Deployed(pool);

        return pool;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}