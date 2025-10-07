// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AITVERC721Base} from "../src/AITVERC721Base.sol";

contract AITVERC721BaseTest is Test {
    AITVERC721Base private _nft;
    address private _owner = address(this);

    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function setUp() public {
        _nft = new AITVERC721Base(_owner, "AITV Season 1 Badges", "AITVS1B", "ipfs://season1/");
    }

    function test_nameAndSymbol() public {
        assertEq(_nft.name(), "AITV Season 1 Badges");
        assertEq(_nft.symbol(), "AITVS1B");
    }

    function test_ownerCanMint() public {
        _nft.mintWithURI(address(0xBEEF), 1, "001.json");
        assertEq(_nft.ownerOf(1), address(0xBEEF));
        assertEq(_nft.tokenURI(1), string(abi.encodePacked("ipfs://season1/", "001.json")));
    }

    function test_revertsIfMintingSameIdTwice() public {
        _nft.mintWithURI(address(0xBEEF), 42, "042.json");
        vm.expectRevert();
        _nft.mintWithURI(address(0xBEEF), 42, "042.json");
    }

    function test_revertsTokenUriForNonexistent() public {
        vm.expectRevert();
        _nft.tokenURI(999);
    }

    function test_setBaseTokenUriEmitsEventAndUpdatesUris() public {
        // mint a token and assert initial URI
        _nft.mintWithURI(address(0xBEEF), 1, "001.json");
        assertEq(_nft.tokenURI(1), string(abi.encodePacked("ipfs://season1/", "001.json")));

        // expect ERC-4906 batch metadata update event
        vm.expectEmit(true, true, true, true, address(_nft));
        emit BatchMetadataUpdate(0, type(uint256).max);

        // update base URI and assert tokenURI reflects new base
        _nft.setBaseTokenURI("ipfs://season2/");
        assertEq(_nft.tokenURI(1), string(abi.encodePacked("ipfs://season2/", "001.json")));
    }

    function test_setBaseTokenUriOnlyOwner() public {
        address nonOwner = address(0xCAFE);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        _nft.setBaseTokenURI("ipfs://malicious/");
    }

    function test_disableMintingOnlyOwnerAndRevertsOnRepeat() public {
        address nonOwner = address(0xD00D);

        // non-owner cannot disable
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        _nft.disableMinting();

        // owner disables once
        _nft.disableMinting();
        assertTrue(_nft.mintingDisabled());

        // second disable reverts with message
        vm.expectRevert(bytes("already disabled"));
        _nft.disableMinting();
    }

    function test_mintWithUriRevertsWhenMintingDisabled() public {
        _nft.disableMinting();

        vm.expectRevert(bytes("minting disabled"));
        _nft.mintWithURI(address(0xBEEF), 2, "002.json");
    }

    function test_totalSupplyIncrementsOnMint() public {
        assertEq(_nft.totalSupply(), 0);

        _nft.mintWithURI(address(0xBEEF), 1, "001.json");
        assertEq(_nft.totalSupply(), 1);

        _nft.mintWithURI(address(0xBEEF), 2, "002.json");
        assertEq(_nft.totalSupply(), 2);
    }
}


