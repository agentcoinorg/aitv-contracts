// SPDX-License-Identifier: MIT
// solhint-disable-next-line compiler-version
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AITVERC721MintableBase
/// @notice ERC721 base with role-based minting and owner-managed baseURI/max supply
contract AITVERC721MintableBase is ERC721, Ownable, AccessControl, IERC4906 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string internal _baseTokenURI;
    uint256 public totalSupply;
    uint256 public maxSupply;

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _initialBaseTokenURI
    ) ERC721(_name, _symbol) Ownable(_owner) {
        _baseTokenURI = _initialBaseTokenURI;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice Mint a token to `_to` with id `_tokenId`
    /// @dev Requires MINTER_ROLE. Token IDs do not need to be sequential.
    function mint(address _to, uint256 _tokenId) external onlyRole(MINTER_ROLE) {
        require(maxSupply != 0, "maxSupply not set");
        require(totalSupply + 1 <= maxSupply, "exceeds maxSupply");
        _safeMint(_to, _tokenId);
        unchecked {
            totalSupply += 1;
        }
    }

    /// @notice Batch mint tokens to recipients with explicit tokenIds
    /// @dev Requires MINTER_ROLE. Token IDs do not need to be sequential.
    function mintBatch(address[] calldata _recipients, uint256[] calldata _tokenIds) external onlyRole(MINTER_ROLE) {
        require(_recipients.length == _tokenIds.length, "length mismatch");
        uint256 n = _recipients.length;
        if (n == 0) return;
        require(maxSupply != 0, "maxSupply not set");
        require(totalSupply + n <= maxSupply, "exceeds maxSupply");

        for (uint256 i = 0; i < n; i++) {
            _safeMint(_recipients[i], _tokenIds[i]);
        }
        unchecked {
            totalSupply += n;
        }
    }

    /// @notice Owner can update the base token URI
    function setBaseTokenURI(string memory _newBaseTokenURI) external onlyOwner {
        _baseTokenURI = _newBaseTokenURI;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    /// @notice Owner can set or update max supply; cannot be below current totalSupply
    function setMaxSupply(uint256 _newMaxSupply) external onlyOwner {
        require(_newMaxSupply >= totalSupply, "below totalSupply");
        maxSupply = _newMaxSupply;
    }

    /// @inheritdoc ERC721
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControl, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || interfaceId == type(IERC4906).interfaceId;
    }
}


