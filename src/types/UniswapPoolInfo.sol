// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct UniswapPoolInfo {
    /// @notice Address of the permit2 contract
    address permit2;
    /// @notice Address of the hook contract
    address hook;
    /// @notice Recipient of the LP ERC721 token
    address lpRecipient;
    /// @notice Fee for the LP
    uint24 lpFee;
    /// @notice Tick spacing for the uniswap pool
    int24 tickSpacing;
}