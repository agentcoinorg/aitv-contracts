// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {SafeCast} from '@uniswap/v4-core/src/libraries/SafeCast.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

abstract contract UniswapPoolDeployer {
    struct PoolInfo {
        IPoolManager poolManager;
        IPositionManager positionManager;
        address collateral;
        address agentToken;
        uint256 collateralAmount; 
        uint256 agentTokenAmount; 
        address lpRecipient;
        uint24 lpFee;
        int24 tickSpacing; 
        uint160 startingPrice; 
        address hook;
        address permit2;
    }

    struct DeploymentInfo {
        uint256 amount0Max;
        uint256 amount1Max;
        int24 tickLower;
        int24 tickUpper;
        bool isNativeCollateral;
    }

    function _createPoolAndAddLiquidity(
        PoolInfo memory _poolInfo
    ) internal virtual returns (PoolKey memory) {
        DeploymentInfo memory deploymentInfo = DeploymentInfo({
            amount0Max: _poolInfo.collateral < _poolInfo.agentToken ? _poolInfo.collateralAmount : _poolInfo.agentTokenAmount,
            amount1Max: _poolInfo.collateral < _poolInfo.agentToken ? _poolInfo.agentTokenAmount : _poolInfo.collateralAmount,
            // Provide full-range liquidity to the pool
            tickLower: TickMath.minUsableTick(_poolInfo.tickSpacing),
            tickUpper: TickMath.maxUsableTick(_poolInfo.tickSpacing),
            isNativeCollateral: _poolInfo.collateral == address(0)
        });

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(_poolInfo.collateral < _poolInfo.agentToken ? _poolInfo.collateral : _poolInfo.agentToken),
            currency1: Currency.wrap(_poolInfo.collateral < _poolInfo.agentToken ? _poolInfo.agentToken : _poolInfo.collateral),
            fee: _poolInfo.lpFee,
            tickSpacing: _poolInfo.tickSpacing,
            hooks: IHooks(_poolInfo.hook)
        });

        _poolInfo.poolManager.initialize(pool, _poolInfo.startingPrice);

        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _poolInfo.startingPrice,
            TickMath.getSqrtPriceAtTick(deploymentInfo.tickLower),
            TickMath.getSqrtPriceAtTick(deploymentInfo.tickUpper),
            deploymentInfo.amount0Max,
            deploymentInfo.amount1Max
        );

        bytes[] memory mintParams = new bytes[](2);

        mintParams[0] = abi.encode(
            pool,
            deploymentInfo.tickLower,
            deploymentInfo.tickUpper,
            liquidity,
            deploymentInfo.amount0Max,
            deploymentInfo.amount1Max,
            _poolInfo.lpRecipient,
            ""
        );
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        if (!deploymentInfo.isNativeCollateral) {
            IERC20(_poolInfo.collateral).approve(address(_poolInfo.permit2), type(uint256).max);
            IAllowanceTransfer(_poolInfo.permit2).approve(
                _poolInfo.collateral,
                address(_poolInfo.positionManager),
                type(uint160).max,
                type(uint48).max
            );
        }

        IERC20(_poolInfo.agentToken).approve(address(_poolInfo.permit2), type(uint256).max);
        IAllowanceTransfer(_poolInfo.permit2).approve(
            _poolInfo.agentToken,
            address(_poolInfo.positionManager),
            type(uint160).max,
            type(uint48).max
        );

        if (deploymentInfo.isNativeCollateral) {
            _poolInfo.positionManager.modifyLiquidities{value: deploymentInfo.amount0Max}(abi.encode(actions, mintParams), block.timestamp);
        } else {
            _poolInfo.positionManager.modifyLiquidities(abi.encode(actions, mintParams), block.timestamp);
        }

        return pool;
    }


}
