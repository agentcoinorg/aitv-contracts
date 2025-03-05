// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from '@uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {BaseHookUpgradeable} from "./BaseHookUpgradeable.sol";
import {FeeInfo} from "./types/FeeInfo.sol";

abstract contract AgentUniswapHookUpgradeable is BaseHookUpgradeable {
    error CannotBeInitializedDirectly();

    /**
     * The hook called before the state of a pool is initialized. Prevents external contracts
     * from initializing pools using our contract as a hook.
     */
    function _beforeInitialize(address, PoolKey calldata, uint160) internal view virtual override returns (bytes4) {
        revert CannotBeInitializedDirectly();
    }

    function _beforeSwap(
        address _sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata _params,
        bytes calldata _hookData
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        IPoolManager poolManager = _getPoolManager();

        uint256 swapAmount = _params.amountSpecified < 0
            ? uint256(-_params.amountSpecified)
            : uint256(_params.amountSpecified);

        Currency feeCurrency = _params.zeroForOne ? _key.currency0 : _key.currency1;

        FeeInfo memory fees = _getFeesForPair(Currency.unwrap(_key.currency0), Currency.unwrap(_key.currency1));
        address collateral = fees.collateral;

        bool isBurn = _params.zeroForOne 
            ? Currency.unwrap(_key.currency0) == collateral
            : Currency.unwrap(_key.currency1) == collateral;

        uint256 totalFee;
        if (isBurn) {
            totalFee = swapAmount * fees.burnBasisAmount / 10000;
            poolManager.take(feeCurrency, address(0), totalFee);
        } else {
            uint256 length = fees.recipients.length;
            for (uint256 i = 0; i < length; i++) {
                uint256 fee = swapAmount * fees.basisAmounts[i] / 10000;
                totalFee += fee;
                poolManager.take(feeCurrency, fees.recipients[i], fee);
            }
        }

        return (BaseHookUpgradeable.beforeSwap.selector, toBeforeSwapDelta(int128(int256(totalFee)), 0), 0);
    }

    /**
     * Defines the Uniswap V4 hooks that are used by our implementation. This will determine
     * the address that our contract **must** be deployed to for Uniswap V4. 
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _getFeesForPair(address currency0, address currency1) internal view virtual returns (FeeInfo memory);
}
