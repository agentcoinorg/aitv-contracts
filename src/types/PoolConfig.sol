// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {UniswapVersion} from "./UniswapVersion.sol";

struct PoolConfig {
    PoolKey poolKey;
    UniswapVersion version;
}