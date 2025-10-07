// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC721Multisend} from "../src/ERC721Multisend.sol";
import {AITVERC721Base} from "../src/AITVERC721Base.sol";

contract ERC721MultisendTest is Test {
    ERC721Multisend private _multisend;
    AITVERC721Base private _nft;
    address private _owner = address(this);
    address private _sender = address(0x5E1f);

    address private _alice = address(0xA11CE);
    address private _bob = address(0xB0B);
    address private _charlie = address(0xC0FFEE);

    function setUp() public {
        _multisend = new ERC721Multisend();
        _nft = new AITVERC721Base(_owner, "AITV Season 1 Rewards", "S1R", "ipfs://season1/");

        // Mint tokens to EOA sender (safe minting to contracts would revert without IERC721Receiver)
        _nft.mintWithURI(_sender, 1, "001.json");
        _nft.mintWithURI(_sender, 2, "002.json");
        _nft.mintWithURI(_sender, 3, "003.json");

        // Approve multisend to move sender's tokens
        vm.prank(_sender);
        _nft.setApprovalForAll(address(_multisend), true);
    }

    function test_MultisendSingleCollection() public {
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        address[] memory recipients = new address[](3);
        recipients[0] = _alice;
        recipients[1] = _bob;
        recipients[2] = _charlie;

        vm.prank(_sender);
        _multisend.multisend(address(_nft), tokenIds, recipients);

        assertEq(_nft.ownerOf(1), _alice);
        assertEq(_nft.ownerOf(2), _bob);
        assertEq(_nft.ownerOf(3), _charlie);
    }

    function test_RevertOnMismatchedArrayLengths() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        address[] memory recipients = new address[](2);
        recipients[0] = _alice;
        recipients[1] = _bob;

        vm.expectRevert(ERC721Multisend.ArrayLengthMismatch.selector);
        vm.prank(_sender);
        _multisend.multisend(address(_nft), tokenIds, recipients);
    }
}


