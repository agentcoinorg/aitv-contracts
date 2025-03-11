// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BalanceDelta, toBalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from '@uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {BaseHookUpgradeable} from "./BaseHookUpgradeable.sol";
import {IFeeSetter} from "./interfaces/IFeeSetter.sol";
import {UniswapFeeInfo} from "./types/UniswapFeeInfo.sol";

contract AgentUniswapHook is OwnableUpgradeable, UUPSUpgradeable, BaseHookUpgradeable, IFeeSetter {
    error CannotBeInitializedDirectly();
    error OnlyOwnerOrController();

    IPoolManager public poolManager;
    address public controller;
    mapping(bytes32 => UniswapFeeInfo) public fees;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _controller,
        address _uniswapPoolManager
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        poolManager = IPoolManager(_uniswapPoolManager);
        controller = _controller;
        validateHookAddress(this);
    }

    function setController(address _controller) external virtual onlyOwner {
        controller = _controller;
    }

    function setFeesForPair(address _tokenA, address _tokenB, UniswapFeeInfo calldata _uniswapFeeInfo) external virtual {
        if (msg.sender != owner() && msg.sender != controller) {
            revert OnlyOwnerOrController();
        }

        address currency0 = _tokenA < _tokenB ? _tokenA : _tokenB;
        address currency1 = _tokenA < _tokenB ? _tokenB : _tokenA;

        bytes32 key = keccak256(abi.encodePacked(currency0, currency1));
        fees[key] = _uniswapFeeInfo;
    }


    /**
     * Defines the Uniswap V4 hooks that are used by our implementation. This will determine
     * the address that our contract **must** be deployed to for Uniswap V4. 
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: true,
            afterDonate: true,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: true,
            afterRemoveLiquidityReturnDelta: true
        });
    }

    function _getFeesForPair(address currency0, address currency1) internal view virtual returns (UniswapFeeInfo memory) {
        bytes32 key = keccak256(abi.encodePacked(currency0, currency1));
        return fees[key];
    }

    function _getPoolManager() internal view virtual override returns (IPoolManager) {
        return poolManager;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function _beforeInitialize(address, PoolKey calldata, uint160) internal virtual override returns (bytes4) {
        return BaseHookUpgradeable.beforeInitialize.selector;
    }

    function _beforeSwap(
        address _sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata _params,
        bytes calldata _hookData
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 swapAmount = _params.amountSpecified < 0
            ? uint256(-_params.amountSpecified)
            : uint256(_params.amountSpecified);

        Currency feeCurrency = _params.zeroForOne ? _key.currency0 : _key.currency1;

        UniswapFeeInfo memory pairFees = _getFeesForPair(Currency.unwrap(_key.currency0), Currency.unwrap(_key.currency1));
        address collateral = pairFees.collateral;

        bool isBurn = _params.zeroForOne 
            ? Currency.unwrap(_key.currency0) == collateral
            : Currency.unwrap(_key.currency1) == collateral;

        uint256 totalFee;
        if (isBurn) {
            totalFee = swapAmount * pairFees.burnBasisAmount / 10_000;
            poolManager.take(feeCurrency, address(0), totalFee);
        } else {
            uint256 length = pairFees.recipients.length;
            for (uint256 i = 0; i < length; i++) {
                uint256 fee = swapAmount * pairFees.basisAmounts[i] / 10_000;
                totalFee += fee;
                poolManager.take(feeCurrency, pairFees.recipients[i], fee);
            }
        }

        return (BaseHookUpgradeable.beforeSwap.selector, toBeforeSwapDelta(int128(int256(totalFee)), 0), 0);
    }

    function _afterInitialize(address, PoolKey calldata, uint160, int24) internal virtual override returns (bytes4) {
        return BaseHookUpgradeable.afterInitialize.selector;
    }

    function _beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        return BaseHookUpgradeable.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal virtual override returns (bytes4) {
        return BaseHookUpgradeable.beforeRemoveLiquidity.selector;
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        return (BaseHookUpgradeable.afterAddLiquidity.selector, toBalanceDelta(0, 0));
    }

    function _afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        return (BaseHookUpgradeable.afterRemoveLiquidity.selector, toBalanceDelta(0, 0));
    }

    function _afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, int128)
    {
        return (BaseHookUpgradeable.afterSwap.selector, 0);
    }

    function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        return BaseHookUpgradeable.beforeDonate.selector;
    }

    function _afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) internal virtual override
        returns (bytes4)
    {
        return BaseHookUpgradeable.afterDonate.selector;
    }
}
