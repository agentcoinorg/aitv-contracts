// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AgentLaunchPool} from "./AgentLaunchPool.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AgentUniswapHookUpgradeable} from "./AgentUniswapHookUpgradeable.sol";
import {ISetupInitialLiquidity} from "./ISetupInitialLiquidity.sol";
import {UniswapPoolDeployer} from "./UniswapPoolDeployer.sol";
import {FeeInfo} from "./types/FeeInfo.sol";

/// @title AgentFactory
/// @notice The following is a contract to deploy agent launch pools
contract AgentFactory is AgentUniswapHookUpgradeable, UniswapPoolDeployer, OwnableUpgradeable, UUPSUpgradeable, ISetupInitialLiquidity {
    error OnlyLaunchPool();

    event Deployed(address launchPool);

    IPoolManager public poolManager;
    IPositionManager public positionManager;
    AgentLaunchPool public launchPoolImplementation;

    mapping(bytes32 => FeeInfo) public fees;
    mapping(address => bool) public isLaunchPool;

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
        launchPoolImplementation = new AgentLaunchPool();
    }

    function deploy(
        AgentLaunchPool.TokenInfo memory _tokenInfo,
        AgentLaunchPool.LaunchPoolInfo memory _launchPoolInfo,
        AgentLaunchPool.DistributionInfo memory _distributionInfo, 
        FeeInfo memory _feeInfo
    ) external virtual onlyOwner returns(AgentLaunchPool) {
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(launchPoolImplementation), 
            abi.encodeCall(AgentLaunchPool.initialize, (
                owner(),
                _tokenInfo,
                _launchPoolInfo,
                _distributionInfo,
                _feeInfo
            ))
        );

        address pool = address(proxy);

        isLaunchPool[pool] = true;

        emit Deployed(pool);

        return AgentLaunchPool(payable(pool));
    }

    function setupInitialLiquidity(address _agentToken, address _collateral, uint256 _agentTokenAmount, uint256 _collateralAmount, FeeInfo memory _feeInfo) external virtual {
        if (!isLaunchPool[msg.sender]) {
            revert OnlyLaunchPool();
        }

        address currency0 = _collateral < _agentToken ? _collateral : _agentToken;
        address currency1 = _collateral < _agentToken ? _agentToken : _collateral;

        bytes32 key = keccak256(abi.encodePacked(currency0, currency1));
        fees[key] = _feeInfo;
       
        _createPoolAndAddLiquidity(
            PoolInfo({
                positionManager: positionManager,
                collateral: _collateral,
                agentToken: _agentToken,
                collateralAmount: _collateralAmount,
                agentTokenAmount: _agentTokenAmount,
                lpRecipient: address(0),
                lpFee: 0,
                tickSpacing: 200,
                startingPrice: 1 * 2**96,
                hook: address(this)
            })
        );
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