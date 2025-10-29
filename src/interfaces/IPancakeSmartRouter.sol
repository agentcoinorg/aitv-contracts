// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library IV3SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
}

interface IPancakeSmartRouter {
    function exactInput(IV3SwapRouter.ExactInputParams calldata params) external payable returns (uint256 amountOut);

    function exactInputSingle(IV3SwapRouter.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external payable returns (uint256 amountOut);

    function multicall(uint256 deadline, bytes[] calldata data) external payable returns (bytes[] memory);

    function multicall(bytes[] calldata data) external payable returns (bytes[] memory);
}

