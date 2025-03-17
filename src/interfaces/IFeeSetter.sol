// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniswapFeeInfo} from "../types/UniswapFeeInfo.sol";

interface IFeeSetter {
    /// @notice Set fees for a pair of tokens
    function setFeesForPair(address _tokenA, address _tokenB, UniswapFeeInfo calldata _uniswapFeeInfo) external;
}
