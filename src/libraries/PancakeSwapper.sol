// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPancakeSmartRouter, IV3SwapRouter} from "../interfaces/IPancakeSmartRouter.sol";
import {PancakeConfig} from "../types/PancakeConfig.sol";

library PancakeSwapper {
    using SafeERC20 for IERC20;

    /// @notice Do an exact-in swap via Pancake Smart Router (v2-style or v3 single)
    /// @param recipient Who receives tokenOut
    /// @param router Pancake Smart Router instance
    /// @param tokenIn The ERC20 token being sold
    /// @param tokenOut The ERC20 token being bought
    /// @param amountIn How much tokenIn to sell
    /// @param amountOutMin Minimum acceptable tokenOut
    /// @param deadline Deadline forwarded to multicall
    /// @param config Pancake config (fee=0 uses v2-style path; >0 uses v3 exactInputSingle)
    /// @param weth WETH address (used as hop for v2-style path when neither side is WETH)
    /// @return amountOut Amount of tokenOut received by recipient
    function swapExactIn(
        address recipient,
        IPancakeSmartRouter router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint128 amountOutMin,
        uint256 deadline,
        PancakeConfig memory config,
        address weth
    ) internal returns (uint256 amountOut) {
        uint256 startBal = IERC20(tokenOut).balanceOf(recipient);

        if (IERC20(tokenIn).allowance(address(this), address(router)) < amountIn) {
            IERC20(tokenIn).forceApprove(address(router), type(uint256).max);
        }

        bytes[] memory calls = new bytes[](1);

        if (config.fee != 0) {
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: config.fee,
                recipient: recipient,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            });
            calls[0] = abi.encodeWithSelector(IPancakeSmartRouter.exactInputSingle.selector, params);
        } else {
            address[] memory path;
            if (tokenIn == weth || tokenOut == weth) {
                path = new address[](2);
                path[0] = tokenIn;
                path[1] = tokenOut;
            } else {
                path = new address[](3);
                path[0] = tokenIn;
                path[1] = weth;
                path[2] = tokenOut;
            }
            calls[0] = abi.encodeWithSelector(
                IPancakeSmartRouter.swapExactTokensForTokens.selector,
                amountIn,
                amountOutMin,
                path,
                recipient
            );
        }

        router.multicall(deadline, calls);

        uint256 endBal = IERC20(tokenOut).balanceOf(recipient);
        return endBal - startBal;
    }
}


