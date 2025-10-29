// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAerodromeRouter {
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function defaultFactory() external view returns (address);

    /// @notice Swap an exact amount of one token for as many as possible of another token using one or more hops
    /// @param amountIn The amount of tokenFrom to send
    /// @param amountOutMin The minimum amount of tokenTo that must be received for the transaction not to revert
    /// @param routes Routing path (single-hop path contains exactly 1 route)
    /// @param to Recipient of the output tokens
    /// @param deadline Timestamp after which the transaction will revert
    /// @return amounts The amounts for each hop (single-hop returns two values: amountIn, amountOut)
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

