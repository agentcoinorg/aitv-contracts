// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AITVERC721Base
/// @notice Base ERC721 using URI storage
contract AITVERC721Base is ERC721URIStorage, Ownable {
    string internal baseTokenURI;

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _baseTokenURI
    ) ERC721(_name, _symbol) Ownable(_owner) {
        baseTokenURI = _baseTokenURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function mintWithURI(address to, uint256 tokenId, string memory tokenUri) external onlyOwner {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenUri);
    }
}


