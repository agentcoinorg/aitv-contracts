// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IAgentLaunchPool} from "./IAgentLaunchPool.sol";
import {AgentUniswapHookUpgradeable} from "./AgentUniswapHookUpgradeable.sol";
import {FeeInfo} from "./types/FeeInfo.sol";

/// @title AgentFactory
/// @notice The following is a contract to deploy agent launch pools
contract AgentFactory is AgentUniswapHookUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    error OnlyLaunchPool();

    event Deployed(address launchPool);

    IPoolManager public poolManager;
    IPositionManager public positionManager;

    mapping(bytes32 => FeeInfo) public fees;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _uniswapPoolManager,
        address _uniswapPositionManager
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        poolManager = IPoolManager(_uniswapPoolManager);
        positionManager = IPositionManager(_uniswapPositionManager);
        validateHookAddress(this);
    }

    function deploy(
        IAgentLaunchPool.TokenInfo memory _tokenInfo,
        IAgentLaunchPool.LaunchPoolInfo memory _launchPoolInfo,
        IAgentLaunchPool.DistributionInfo memory _distributionInfo, 
        FeeInfo memory _feeInfo,
        address _launchPoolImplementation
    ) external virtual onlyOwner returns(address) {
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(_launchPoolImplementation), 
            abi.encodeCall(IAgentLaunchPool.initialize, (
                owner(),
                _tokenInfo,
                _launchPoolInfo,
                _distributionInfo,
                positionManager
            ))
        );

        address pool = address(proxy);

        address collateral = _launchPoolInfo.collateral;
        address agentToken = IAgentLaunchPool(pool).computeAgentTokenAddress();

        address currency0 = collateral < agentToken ? collateral : agentToken;
        address currency1 = collateral < agentToken ? agentToken : collateral;

        bytes32 key = keccak256(abi.encodePacked(currency0, currency1));
        fees[key] = _feeInfo;

        emit Deployed(pool);

        return pool;
    }

    function _getPoolManager() internal view virtual override returns (IPoolManager) {
        return poolManager;
    }

    function _getFeesForPair(address currency0, address currency1) internal view virtual override returns (FeeInfo memory) {
        bytes32 key = keccak256(abi.encodePacked(currency0, currency1));
        return fees[key];
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}