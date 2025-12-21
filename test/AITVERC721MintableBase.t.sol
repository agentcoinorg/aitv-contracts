// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AITVERC721MintableBase} from "../src/AITVERC721MintableBase.sol";

contract AITVERC721MintableBaseTest is Test {
    AITVERC721MintableBase private _nft;
    address private _owner = address(this);

    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function setUp() public {
        _nft = new AITVERC721MintableBase(_owner, "AITV Badges", "AITVB", "ipfs://base/");
        _nft.setMaxSupply(10);
    }

    function test_nameAndSymbol() public {
        assertEq(_nft.name(), "AITV Badges");
        assertEq(_nft.symbol(), "AITVB");
    }

    function test_setBaseTokenUriEmitsEvent() public {
        vm.expectEmit(true, true, true, true, address(_nft));
        emit BatchMetadataUpdate(0, type(uint256).max);
        _nft.setBaseTokenURI("ipfs://newbase/");
    }

    function test_setMaxSupplyOnlyOwner() public {
        address nonOwner = address(0xBEEF);
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        _nft.setMaxSupply(100);

        _nft.setMaxSupply(5);
        assertEq(_nft.maxSupply(), 5);
    }

    function test_setMaxSupplyCannotGoBelowTotalSupply() public {
        address minter = address(0xA11CE);
        _nft.grantRole(_nft.MINTER_ROLE(), minter);

        vm.prank(minter);
        _nft.mint(address(0x1), 100);
        assertEq(_nft.totalSupply(), 1);

        vm.expectRevert(bytes("below totalSupply"));
        _nft.setMaxSupply(0);
    }

    function test_mintRequiresMinterRole() public {
        address nonMinter = address(0xCAFE);
        vm.prank(nonMinter);
        vm.expectRevert(); // AccessControl revert
        _nft.mint(address(0x1), 1);
    }

    function test_minterCanMintNonSequentialAndRespectsMaxSupply() public {
        address minter = address(0xA11CE);
        _nft.grantRole(_nft.MINTER_ROLE(), minter);
        _nft.setMaxSupply(2);

        vm.prank(minter);
        _nft.mint(address(0x1), 100);
        vm.prank(minter);
        _nft.mint(address(0x2), 2);

        assertEq(_nft.ownerOf(100), address(0x1));
        assertEq(_nft.ownerOf(2), address(0x2));
        assertEq(_nft.totalSupply(), 2);

        vm.prank(minter);
        vm.expectRevert(bytes("exceeds maxSupply"));
        _nft.mint(address(0x3), 3);
    }

    function test_batchMintAllowsNonSequentialAndCounts() public {
        address minter = address(0xB0B);
        _nft.grantRole(_nft.MINTER_ROLE(), minter);
        _nft.setMaxSupply(5);

        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1);
        recipients[1] = address(0x2);
        recipients[2] = address(0x3);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 5;
        tokenIds[1] = 1;
        tokenIds[2] = 3;

        vm.prank(minter);
        _nft.mintBatch(recipients, tokenIds);

        assertEq(_nft.ownerOf(5), address(0x1));
        assertEq(_nft.ownerOf(1), address(0x2));
        assertEq(_nft.ownerOf(3), address(0x3));
        assertEq(_nft.totalSupply(), 3);
    }

    function test_batchMintRevertsOnLengthMismatch() public {
        address minter = address(0xB0B);
        _nft.grantRole(_nft.MINTER_ROLE(), minter);

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x1);
        recipients[1] = address(0x2);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 10;

        vm.prank(minter);
        vm.expectRevert(bytes("length mismatch"));
        _nft.mintBatch(recipients, tokenIds);
    }

    function test_batchMintRevertsWhenExceedsMaxSupplyByCount() public {
        address minter = address(0xB0B);
        _nft.grantRole(_nft.MINTER_ROLE(), minter);
        _nft.setMaxSupply(1);

        address[] memory recipients = new address[](2);
        recipients[0] = address(0x1);
        recipients[1] = address(0x2);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 10;
        tokenIds[1] = 11;

        vm.prank(minter);
        vm.expectRevert(bytes("exceeds maxSupply"));
        _nft.mintBatch(recipients, tokenIds);
    }
}



