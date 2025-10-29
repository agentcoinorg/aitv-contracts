// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAerodromeRouter} from "../interfaces/IAerodromeRouter.sol";

library AerodromeSwapper {
    using SafeERC20 for IERC20;
    function swapExactIn(
        address recipient,
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        bool stable,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        uint256 startBal = IERC20(tokenOut).balanceOf(recipient);

        if (tokenIn != address(0)) {
            if (IERC20(tokenIn).allowance(address(this), router) < amountIn) {
                // Use forceApprove to support non-standard ERC20s
                IERC20(tokenIn).forceApprove(router, type(uint256).max);
            }
            // Build single-hop route using router's default factory.
            address factory = IAerodromeRouter(router).defaultFactory();
            IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
            routes[0] = IAerodromeRouter.Route({from: tokenIn, to: tokenOut, stable: stable, factory: factory});

            // Execute swap with the configured pool type only.
            IAerodromeRouter(router).swapExactTokensForTokens(amountIn, amountOutMin, routes, recipient, deadline);
        } else {
            revert("Aerodrome ETH path not supported here");
        }

        uint256 endBal = IERC20(tokenOut).balanceOf(recipient);
        return endBal - startBal;
    }
}


