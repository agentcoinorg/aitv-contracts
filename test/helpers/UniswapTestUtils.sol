// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionInfo} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";

abstract contract UniswapTestUtils is Test {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    
    address public uniswapPoolManager;
    address public uniswapPositionManager;
    address public uniswapUniversalRouter;
    address permit2 = vm.envAddress("PERMIT2");
    address weth = vm.envAddress("WETH");

    function _swapETHForERC20ExactIn(
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

    function _swapETHForERC20ExactOut(
        address user,
        PoolKey memory key,
        uint256 outAmount
    ) internal returns (uint256 spentAmount) {
        vm.startPrank(user);

        uint256 startETHAmount = user.balance;

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP), uint8(Commands.SWEEP));
        bytes[] memory inputs = new bytes[](2);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountInMaximum: uint128(user.balance),
                amountOut: uint128(outAmount),
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(key.currency0, uint128(user.balance));
        params[2] = abi.encode(key.currency1, uint128(outAmount));

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);
        inputs[1] = abi.encode(key.currency0, user);
       
        IUniversalRouter(uniswapUniversalRouter).execute{value: user.balance}(commands, inputs, block.timestamp);

        uint256 endETHAmount = user.balance;
        
        vm.stopPrank();

        return startETHAmount - endETHAmount;
    }

    function _swapERC20ForERC20ExactIn(
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

    function _swapERC20ForERC20ExactOut(
        address user,
        PoolKey memory key,
        uint256 outAmount,
        address inToken
    ) internal returns (uint256 amountSpent) {
        vm.startPrank(user);
       
        uint256 startInTokenAmount = Currency.unwrap(key.currency0) == inToken
            ? IERC20(Currency.unwrap(key.currency0)).balanceOf(address(user))
            : IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user));

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bool zeroForOne = Currency.unwrap(key.currency0) == inToken;

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountInMaximum: uint128(startInTokenAmount),
                amountOut: uint128(outAmount),
                hookData: bytes("")
            })
        );
        if (zeroForOne) {
            params[1] = abi.encode(key.currency0, uint128(startInTokenAmount));
            params[2] = abi.encode(key.currency1, 0);
        } else {
            params[1] = abi.encode(key.currency1, uint128(startInTokenAmount));
            params[2] = abi.encode(key.currency0, 0);
        }

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);
        // inputs[1] = abi.encode(key.currency0, user);
        // inputs[2] = abi.encode(key.currency1, user);

        _approvePermit2(inToken, startInTokenAmount, 0);    
        IUniversalRouter(uniswapUniversalRouter).execute(commands, inputs, block.timestamp);

        uint256 endInTokenAmount = Currency.unwrap(key.currency0) == inToken
            ? IERC20(Currency.unwrap(key.currency0)).balanceOf(address(user))
            : IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user));
        
        vm.stopPrank();
     
        return startInTokenAmount - endInTokenAmount;
    }

    function _swapERC20ForETHExactIn(
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

    function _swapERC20ForETHExactOut(
        address user,
        PoolKey memory key,
        uint256 outAmount
    ) internal returns (uint256 amountSpent) {
        vm.startPrank(user);

        uint256 startERC20Amount = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user));

        console.logUint(startERC20Amount);

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: false,
                amountInMaximum: uint128(startERC20Amount),
                amountOut: uint128(outAmount),
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(key.currency1, uint128(startERC20Amount));
        params[2] = abi.encode(key.currency0, 0);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        _approvePermit2(Currency.unwrap(key.currency1), startERC20Amount, 0);    
        IUniversalRouter(uniswapUniversalRouter).execute(commands, inputs, block.timestamp);

        uint256 endERC20Amount = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(user));
        
        vm.stopPrank();
     
        return startERC20Amount - endERC20Amount;
    }

    function _getLiquidity(PoolKey memory poolKey, address tokenA, int24 tickSpacing) internal view returns (uint256 reserveA, uint256 reserveB, uint totalLiquidity) {
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(uniswapPoolManager), poolKey.toId());

        uint128 liquidity = StateLibrary.getLiquidity(IPoolManager(uniswapPoolManager), poolKey.toId());

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(tickSpacing)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(tickSpacing)),
            liquidity
        );

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

    function _mintLiquidityPosition(address provider, PoolKey memory poolKey, uint256 amount0Max, uint256 amount1Max, int24 tickSpacing) internal returns (uint256 tokenId) {
        tokenId = IPositionManager(uniswapPositionManager).nextTokenId();
        vm.startPrank(provider);
        {
            (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(uniswapPoolManager), poolKey.toId());
   
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(tickSpacing)),
                TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(tickSpacing)),
                uint160(amount0Max),
                uint160(amount1Max)
            );

            bytes[] memory mintParams = new bytes[](4);

            mintParams[0] = abi.encode(
                poolKey,
                TickMath.minUsableTick(tickSpacing),
                TickMath.maxUsableTick(tickSpacing),
                liquidity,
                uint160(amount0Max),
                uint160(amount1Max),
                provider,
                ""
            );
            mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);
            mintParams[2] = abi.encode(poolKey.currency0, provider);
            mintParams[3] = abi.encode(poolKey.currency1, provider);

            bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP));

            if (!poolKey.currency0.isAddressZero()) {
                address token0 = Currency.unwrap(poolKey.currency0);
                IERC20(token0).approve(address(permit2), type(uint256).max);
                IAllowanceTransfer(permit2).approve(
                    token0,
                    uniswapPositionManager,
                    type(uint160).max,
                    type(uint48).max
                );
            }
            address token1 = Currency.unwrap(poolKey.currency1);
            IERC20(token1).approve(address(permit2), type(uint256).max);
            IAllowanceTransfer(permit2).approve(
                token1,
                uniswapPositionManager,
                type(uint160).max,
                type(uint48).max
            );

            uint256 value = poolKey.currency0.isAddressZero()
                ? amount0Max
                : 0;
         
            IPositionManager(uniswapPositionManager).modifyLiquidities{value: value}(abi.encode(actions, mintParams), block.timestamp);
        }
        vm.stopPrank();

        return tokenId;
    }

    function _mintLiquidityPositionExpectRevert(address provider, PoolKey memory poolKey, uint256 amount0Max, uint256 amount1Max, int24 tickSpacing) internal returns (uint256 tokenId) {
        tokenId = IPositionManager(uniswapPositionManager).nextTokenId();
        vm.startPrank(provider);
        {
            (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(uniswapPoolManager), poolKey.toId());
   
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(tickSpacing)),
                TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(tickSpacing)),
                uint160(amount0Max),
                uint160(amount1Max)
            );

            bytes[] memory mintParams = new bytes[](4);

            mintParams[0] = abi.encode(
                poolKey,
                TickMath.minUsableTick(tickSpacing),
                TickMath.maxUsableTick(tickSpacing),
                liquidity,
                uint160(amount0Max),
                uint160(amount1Max),
                provider,
                ""
            );
            mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);
            mintParams[2] = abi.encode(poolKey.currency0, provider);
            mintParams[3] = abi.encode(poolKey.currency1, provider);

            bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP));

            if (!poolKey.currency0.isAddressZero()) {
                address token0 = Currency.unwrap(poolKey.currency0);
                IERC20(token0).approve(address(permit2), type(uint256).max);
                IAllowanceTransfer(permit2).approve(
                    token0,
                    uniswapPositionManager,
                    type(uint160).max,
                    type(uint48).max
                );
            }
            address token1 = Currency.unwrap(poolKey.currency1);
            IERC20(token1).approve(address(permit2), type(uint256).max);
            IAllowanceTransfer(permit2).approve(
                token1,
                uniswapPositionManager,
                type(uint160).max,
                type(uint48).max
            );

            uint256 value = poolKey.currency0.isAddressZero()
                ? amount0Max
                : 0;
         
            vm.expectRevert(); // Uniswap wraps the error, so we can't check the message
            IPositionManager(uniswapPositionManager).modifyLiquidities{value: value}(abi.encode(actions, mintParams), block.timestamp);
        }
        vm.stopPrank();

        return tokenId;
    }

    function _collectLiquidityProviderFees(address provider, uint256 tokenId, PoolKey memory poolKey) internal {
        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, 0, 0, 0, "");

        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, provider);
        
        vm.prank(provider);
        IPositionManager(uniswapPositionManager).modifyLiquidities(abi.encode(actions, params), block.timestamp);
    }

    function _getPositionDetails(uint256 tokenId) internal view returns (PositionDetails memory) {
        // Fetch the pool key and position details
        (PoolKey memory poolKey, PositionInfo posInfo) =
            IPositionManager(uniswapPositionManager).getPoolAndPositionInfo(tokenId);

        // Get the current liquidity
        uint128 liquidity = IPositionManager(uniswapPositionManager).getPositionLiquidity(tokenId);

        // Get the pool's current sqrtPriceX96 and tick from StateLibrary
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(uniswapPoolManager), poolKey.toId());

        // Get sqrt price at tickLower and tickUpper
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(posInfo.tickLower());
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(posInfo.tickUpper());

        // Compute token amounts based on liquidity and current price
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, sqrtPriceLower, sqrtPriceUpper, liquidity
        );

        return PositionDetails(liquidity, amount0, amount1);
    }

    struct PositionDetails{
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }
}
