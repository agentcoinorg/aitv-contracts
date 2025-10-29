// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct PancakeConfig {
    uint24 fee; // v3 pool fee if applicable; 0 means use v2-style routing
    bool exists;
}

struct PancakeProposal {
    address tokenA;
    address tokenB;
    uint24 fee; // v3 fee tier for tokenA-tokenB
}


