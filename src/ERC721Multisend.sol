// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title ERC721Multisend
/// @notice Batch transfer helper for ERC721 tokens using transferFrom
/// @dev Sender must have approved this contract for each collection (setApprovalForAll or approve per token)
contract ERC721Multisend {
    error ArrayLengthMismatch();

    /// @notice Transfer multiple ERC721 tokens from a single collection to recipients
    /// @param _collection ERC721 collection address
    /// @param _tokenIds Array of token IDs to transfer (aligned with recipients)
    /// @param _recipients Array of recipient addresses to receive the tokens
    function multisend(
        address _collection,
        uint256[] calldata _tokenIds,
        address[] calldata _recipients
    ) external {
        uint256 length = _tokenIds.length;
        if (length != _recipients.length) revert ArrayLengthMismatch();

        IERC721 erc721 = IERC721(_collection);
        for (uint256 i = 0; i < length; i++) {
            // Caller must be owner or approved, and must have approved this contract via setApprovalForAll
            erc721.transferFrom(msg.sender, _recipients[i], _tokenIds[i]);
        }
    }
}


