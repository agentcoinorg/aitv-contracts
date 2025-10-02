// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {AITVERC721Base} from "../src/AITVERC721Base.sol";

contract Season1RewardsTest is Test {
    AITVERC721Base private _nft;
    address private _owner = address(this);

    function setUp() public {
        _nft = new AITVERC721Base(_owner, "AITV Season 1 Rewards", "S1R", "ipfs://season1/");
    }

    function testNameAndSymbol() public {
        assertEq(_nft.name(), "AITV Season 1 Rewards");
        assertEq(_nft.symbol(), "S1R");
    }

    function testOwnerCanMint() public {
        _nft.mintWithURI(address(0xBEEF), 1, "001.json");
        assertEq(_nft.ownerOf(1), address(0xBEEF));
        assertEq(_nft.tokenURI(1), string(abi.encodePacked("ipfs://season1/", "001.json")));
    }

    function testRevertsIfMintingSameIdTwice() public {
        _nft.mintWithURI(address(0xBEEF), 42, "042.json");
        vm.expectRevert();
        _nft.mintWithURI(address(0xBEEF), 42, "042.json");
    }

    function testRevertsTokenURIForNonexistent() public {
        vm.expectRevert();
        _nft.tokenURI(999);
    }
}


