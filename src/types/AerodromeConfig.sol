// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct AerodromeConfig {
    bool stable;
    bool exists;
}

struct AerodromeProposal {
    address tokenA;
    address tokenB;
    bool stable;
}


