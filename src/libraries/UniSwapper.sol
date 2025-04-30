// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import {UniswapVersion} from "../types/UniswapVersion.sol";


library UniSwapper {
    /// @notice Do an “exact-in” swap on Uniswap V2, V3 or V4 (via Universal Router)
    /// @param recipient       who gets the `tokenOut`
    /// @param key             the PoolKey (for V3/V4)
    /// @param tokenIn         the token you’re selling
    /// @param tokenOut        the token you want to buy
    /// @param amountIn        how much of `tokenIn` to sell
    /// @param amountOutMin    the minimum you’ll accept of `tokenOut`
    /// @param version         which router version to hit
    /// @param universalRouter the address of your Universal Router
    /// @return amountOut      how many `tokenOut` landed in `recipient`
    function swapExactIn(
        address recipient,
        PoolKey memory key,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint128 amountOutMin,
        UniswapVersion version,
        IUniversalRouter universalRouter,
        IPermit2 permit2
    ) internal returns (uint256 amountOut) {
        uint256 startBal = tokenOut == address(0) 
            ? address(recipient).balance
            : IERC20(tokenOut).balanceOf(recipient);

        if (tokenIn != address(0)) {
            if (IERC20(tokenIn).allowance(address(this), address(permit2)) < type(uint256).max) {
                IERC20(tokenIn).approve(address(permit2), type(uint256).max);
            }

            IPermit2(permit2).approve(tokenIn, address(universalRouter), uint160(amountIn), 0);
        }

        bytes memory commands = abi.encodePacked(
            version == UniswapVersion.V2 ? uint8(Commands.V2_SWAP_EXACT_IN) :
            version == UniswapVersion.V3 ? uint8(Commands.V3_SWAP_EXACT_IN) :
                                     uint8(Commands.V4_SWAP)
        );

        bytes[] memory inputs = new bytes[](1);

        if (version == UniswapVersion.V2) {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            inputs[0] = abi.encode(
              ActionConstants.MSG_SENDER,
              amountIn,
              amountOutMin,
              path,
              true
            );
        } else if (version == UniswapVersion.V3) {
            bytes memory path = abi.encodePacked(tokenIn, uint24(key.fee), tokenOut);
            inputs[0] = abi.encode(
                recipient,
                amountIn,
                amountOutMin,
                path,
                true
            );
        } else {
            bool zeroForOne;

            if (tokenIn == Currency.unwrap(key.currency0) && tokenOut == Currency.unwrap(key.currency1)) {
                zeroForOne = true;
            } else if (tokenIn == Currency.unwrap(key.currency1) && tokenOut == Currency.unwrap(key.currency0)) {
                zeroForOne = false;
            } else {
                revert("UniSwapper: invalid tokenIn/out");
            }

            bytes memory actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN_SINGLE),
                uint8(Actions.SETTLE_ALL),
                uint8(Actions.TAKE_ALL)
            );

            bytes[] memory params = new bytes[](3);
            params[0] = abi.encode(
                key,
                zeroForOne,
                uint128(amountIn),
                amountOutMin,
                bytes("") 
            );
            params[1] = abi.encode(tokenIn, uint128(amountIn));
            params[2] = abi.encode(tokenOut, amountOutMin);

            inputs[0] = abi.encode(actions, params);
        }

        universalRouter.execute{ value: (tokenIn == address(0) ? amountIn : 0) }(
            commands,
            inputs,
            block.timestamp
        );

        uint256 endBal = tokenOut == address(0)
            ? address(recipient).balance 
            : IERC20(tokenOut).balanceOf(recipient);
        
        return endBal - startBal;
    }
}
