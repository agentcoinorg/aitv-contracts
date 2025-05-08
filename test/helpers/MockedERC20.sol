// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract MockedERC20 is MockERC20 {
    constructor() {
        initialize("MockedERC20", "MERC", 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}