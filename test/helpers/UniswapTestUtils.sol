// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Currency } from '@uniswap/v4-core/src/types/Currency.sol';
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {IAgentLaunchPool} from "../../src/interfaces/IAgentLaunchPool.sol";
import {TokenInfo} from "../../src/types/TokenInfo.sol";
import {LaunchPoolInfo} from "../../src/types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "../../src/types/UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "../../src/types/AgentDistributionInfo.sol";
import {UniswapFeeInfo} from "../../src/types/UniswapFeeInfo.sol";
import {AgentFactory} from "../../src/AgentFactory.sol";
import {AgentUniswapHookDeployer} from "../../src/AgentUniswapHookDeployer.sol";
import {AgentUniswapHook} from "../../src/AgentUniswapHook.sol";
import {AgentToken} from "../../src/AgentToken.sol";
import {AgentStaking} from "../../src/AgentStaking.sol";

abstract contract UniswapTestUtils is Test {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    
    address public uniswapPoolManager;
    address public uniswapUniversalRouter;
    address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function _swapETHForERC20(
        address user,
        PoolKey memory key,
        uint256 inAmount
    ) internal returns (uint256 amountOut) {
        vm.startPrank(user);

        uint256 startERC20Amount = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user));

        uint128 minAmountOut = 0;
      
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: uint128(inAmount),
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(key.currency0, uint128(inAmount));
        params[2] = abi.encode(key.currency1, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        IUniversalRouter(uniswapUniversalRouter).execute{value: inAmount}(commands, inputs, block.timestamp);

        uint256 endERC20Amount = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user));
        
        vm.stopPrank();

        return endERC20Amount - startERC20Amount;
    }

    function _swapERC20ForERC20(
        address user,
        PoolKey memory key,
        uint256 inAmount,
        address inToken
    ) internal returns (uint256 amountOut) {
        vm.startPrank(user);
       
        uint256 startOutTokenAmount = Currency.unwrap(key.currency0) == inToken
            ? IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user))
            : IERC20(Currency.unwrap(key.currency0)).balanceOf(address(user));

        uint128 minAmountOut = 0;
       
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bool zeroForOne = Currency.unwrap(key.currency0) == inToken;

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: uint128(inAmount),
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        if (zeroForOne) {
            params[1] = abi.encode(key.currency0, uint128(inAmount));
            params[2] = abi.encode(key.currency1, minAmountOut);
        } else {
            params[1] = abi.encode(key.currency1, uint128(inAmount));
            params[2] = abi.encode(key.currency0, minAmountOut);
        }

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        _approvePermit2(inToken, inAmount, 0);    
        IUniversalRouter(uniswapUniversalRouter).execute(commands, inputs, block.timestamp);

        uint256 endOutTokenAmount = Currency.unwrap(key.currency0) == inToken
            ? IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user))
            : IERC20(Currency.unwrap(key.currency0)).balanceOf(address(user));
        
        vm.stopPrank();
     
        return endOutTokenAmount - startOutTokenAmount;
    }

    function _swapERC20ForETH(
        address user,
        PoolKey memory key,
        uint256 inAmount
    ) internal returns (uint256 amountOut) {
        vm.startPrank(user);

        uint256 startETHAmount = user.balance;

        uint128 minAmountOut = 0;

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: false,
                amountIn: uint128(inAmount),
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(key.currency1, uint128(inAmount));
        params[2] = abi.encode(key.currency0, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        _approvePermit2(Currency.unwrap(key.currency1), inAmount, 0);    
        IUniversalRouter(uniswapUniversalRouter).execute(commands, inputs, block.timestamp);

        uint256 endETHAmount = user.balance;
        
        vm.stopPrank();
     
        return endETHAmount - startETHAmount;
    }

    function _getLiquidity(PoolKey memory poolKey, address tokenA, address tokenB, int24 tickSpacing) internal view returns (uint256 reserveA, uint256 reserveB, uint totalLiquidity) {
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(uniswapPoolManager), poolKey.toId());

        uint128 liquidity = StateLibrary.getLiquidity(IPoolManager(uniswapPoolManager), poolKey.toId());
        console.logUint(liquidity);
        console.logUint(1337);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(tickSpacing)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(tickSpacing)),
            liquidity
        );
        console.logUint(amount0);
        console.logUint(amount1);

        return Currency.unwrap(poolKey.currency0) == tokenA
            ? (amount0, amount1, liquidity)
            : (amount1, amount0, liquidity);
    }

    function _approvePermit2(
        address token,
        uint256 amount,
        uint48 expiration
    ) internal {
        IERC20(token).approve(permit2, type(uint256).max);
        IPermit2(permit2).approve(token, address(uniswapUniversalRouter), uint160(amount), expiration);
    }
}