// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AITVERC721Base
/// @notice Base ERC721 using URI storage
contract AITVERC721Base is ERC721URIStorage, Ownable {
    string internal baseTokenURI;
    uint256 public totalSupply;
    bool public mintingDisabled;

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

    function mintWithURI(address _to, uint256 _tokenId, string memory _tokenUri) external onlyOwner {
        require(!mintingDisabled, "minting disabled");
        _safeMint(_to, _tokenId);
        _setTokenURI(_tokenId, _tokenUri);
        unchecked {
            totalSupply += 1;
        }
    }

    function setBaseTokenURI(string memory _newBaseTokenURI) external onlyOwner {
        baseTokenURI = _newBaseTokenURI;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function disableMinting() external onlyOwner {
        require(!mintingDisabled, "already disabled");
        mintingDisabled = true;
    }
}


