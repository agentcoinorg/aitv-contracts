// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
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
import {DistributionAndPriceChecker} from "./DistributionAndPriceChecker.sol";

/// @title AgentFactory
/// @notice The following is a contract to deploy agent launch pools
/// @dev It is responsible for setting the fees for the uniswap pool and authorizing the launch pool with the uniswap hook
contract AgentFactory is DistributionAndPriceChecker, Ownable2StepUpgradeable, UUPSUpgradeable {
    error LengthMismatch();
    error ZeroAddressNotAllowed();

    event DeployLaunchPool(address launchPool);
    event AddProposal(uint256 proposalId, address proposer);
    event DeployProposal(uint256 proposalId, address launchPool);

    IPoolManager public poolManager;
    IPositionManager public positionManager;

    LaunchPoolProposal[] public proposals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract and the one who can upgrade it
    /// @param _uniswapPoolManager The address of the uniswap pool manager
    /// @param _positionManager The address of the position manager
    function initialize(
        address _owner,
        address _uniswapPoolManager,
        address _positionManager
    ) external initializer {
        if (_uniswapPoolManager == address(0) || _positionManager == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        __Ownable_init(_owner); // Checks for zero address
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        poolManager = IPoolManager(_uniswapPoolManager);
        positionManager = IPositionManager(_positionManager);
    }

    /// @notice Adds a proposal to the factory
    /// @dev Anyone can add a proposal, but only the owner can deploy it
    /// @param _proposal The proposal to add
    /// @return The id of the proposal
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

        if (_proposal.launchPoolImplementation == address(0)
            || _proposal.tokenInfo.owner == address(0) 
            || _proposal.tokenInfo.tokenImplementation == address(0) 
            || _proposal.tokenInfo.stakingImplementation == address(0) 
            || _proposal.uniswapPoolInfo.permit2 == address(0)
            || _proposal.uniswapPoolInfo.hook == address(0)
        ) {
            revert ZeroAddressNotAllowed();
        }

        _requireCorrectDistribution(_proposal.launchPoolInfo, _proposal.distributionInfo);

        proposals.push(_proposal);

        uint256 proposalId = proposals.length - 1;

        emit AddProposal(proposalId, msg.sender);

        return proposalId;
    }

    /// @notice Deploys a proposal
    /// @param proposalId The id of the proposal to deploy
    /// @return The address of the deployed launch pool
    function deployProposal(uint256 proposalId) external virtual onlyOwner returns(address payable) {
        LaunchPoolProposal memory proposal = proposals[proposalId];

        address payable pool = _deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );

        emit DeployProposal(proposalId, pool);

        return pool;
    }

    /// @notice Getter for a proposal
    /// @param _proposalId The id of the proposal
    /// @return The proposal
    function getProposal(uint256 _proposalId) external view returns(LaunchPoolProposal memory) {
        return proposals[_proposalId];
    }

    /// @notice Deploys a launch pool
    /// @dev Only the owner can deploy a launch pool, and the distribution must be correct
    /// It sets the fees and the launch pool as authorized on the uniswap hook
    /// @param _launchPoolImplementation The address of the launch pool implementation
    /// @param _tokenInfo The token information
    /// @param _launchPoolInfo The launch pool information
    /// @param _uniswapPoolInfo The uniswap pool information
    /// @param _distributionInfo The distribution information
    /// @param _uniswapFeeInfo The uniswap fee information
    /// @return The address of the deployed launch pool
    function deploy(
        address _launchPoolImplementation,
        TokenInfo calldata _tokenInfo,
        LaunchPoolInfo calldata _launchPoolInfo,
        UniswapPoolInfo calldata _uniswapPoolInfo,
        AgentDistributionInfo calldata _distributionInfo,
        UniswapFeeInfo calldata _uniswapFeeInfo
    ) external virtual onlyOwner returns(address payable) {
        return _deploy(
            _launchPoolImplementation,
            _tokenInfo,
            _launchPoolInfo,
            _uniswapPoolInfo,
            _distributionInfo,
            _uniswapFeeInfo
        );
    }

    /// @notice Deploys a launch pool
    /// @dev Only the owner can deploy a launch pool, and the distribution must be correct
    /// It sets the fees and the launch pool as authorized on the uniswap hook
    /// @param _launchPoolImplementation The address of the launch pool implementation
    /// @param _tokenInfo The token information
    /// @param _launchPoolInfo The launch pool information
    /// @param _uniswapPoolInfo The uniswap pool information
    /// @param _distributionInfo The distribution information
    /// @param _uniswapFeeInfo The uniswap fee information
    /// @return The address of the deployed launch pool
    function _deploy(
        address _launchPoolImplementation,
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        UniswapFeeInfo memory _uniswapFeeInfo
    ) internal returns(address payable) {
        if (_launchPoolInfo.collateralRecipients.length != _launchPoolInfo.collateralBasisAmounts.length) {
            revert LengthMismatch();
        }

        if (_distributionInfo.recipients.length != _distributionInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        if (_uniswapFeeInfo.recipients.length != _uniswapFeeInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        if (_launchPoolImplementation == address(0)
            || _tokenInfo.owner == address(0) 
            || _tokenInfo.tokenImplementation == address(0) 
            || _tokenInfo.stakingImplementation == address(0) 
            || _uniswapPoolInfo.permit2 == address(0)
            || _uniswapPoolInfo.hook == address(0)
        ) {
            revert ZeroAddressNotAllowed();
        }

        _requireCorrectDistribution(_launchPoolInfo, _distributionInfo);
      
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

        emit DeployLaunchPool(pool);

        return payable(pool);
    }

    /// @notice Access control to upgrade the contract. Only the owner can upgrade
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
