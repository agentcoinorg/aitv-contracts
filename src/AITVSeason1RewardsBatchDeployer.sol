// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AITVERC721Base} from "./AITVERC721Base.sol";

/// @title AITVSeason1RewardsBatchDeployer
/// @notice Deploys the S1R NFT, allows parameterized, chunked minting with padded URIs, then transfers ownership
contract AITVSeason1RewardsBatchDeployer {
    AITVERC721Base public immutable nft;
    address public immutable recipient;
    address public immutable finalOwner;
    uint256 public immutable totalToMint;
    uint256 public nextTokenIdToMint;

    event BatchMinted(uint256 indexed startTokenId, uint256 indexed endTokenId, uint256 count);
    event Finalized(address indexed newOwner);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory baseTokenURI,
        address _recipient,
        address _finalOwner,
        uint256 _totalToMint
    ) {
        require(_recipient != address(0), "recipient zero");
        require(_finalOwner != address(0), "owner zero");
        require(_totalToMint > 0, "total = 0");

        // Deploy the NFT with this contract as the temporary owner so we can batch mint
        nft = new AITVERC721Base(address(this), _name, _symbol, baseTokenURI);

        recipient = _recipient;
        finalOwner = _finalOwner;
        totalToMint = _totalToMint;
        nextTokenIdToMint = 1; // token IDs start at 1
    }

    /// @notice Mints up to `batchSize` tokens to the fixed recipient. Returns how many were minted.
    ///         This function can be called multiple times across separate transactions until `totalToMint` is reached.
    function mintNextBatch(uint256 batchSize) external returns (uint256 mintedCount) {
        require(batchSize > 0, "batchSize = 0");
        uint256 startId = nextTokenIdToMint;
        if (startId > totalToMint) {
            return 0; // nothing left to mint
        }

        uint256 remaining = totalToMint - (startId - 1);
        uint256 toMint = batchSize < remaining ? batchSize : remaining;

        uint256 endExclusive = startId + toMint; // mint [startId, endExclusive)
        for (uint256 i = startId; i < endExclusive; i++) {
            nft.mintWithURI(recipient, i, string(abi.encodePacked(_padded(i), ".json")));
        }

        nextTokenIdToMint = endExclusive;
        mintedCount = toMint;
        emit BatchMinted(startId, endExclusive - 1, mintedCount);
    }

    /// @notice Transfers ownership of the NFT to the final owner. Can only be done once all tokens are minted.
    function finalize() external {
        require(nextTokenIdToMint - 1 == totalToMint, "not fully minted");
        nft.transferOwnership(finalOwner);
        emit Finalized(finalOwner);
    }

    function remainingToMint() external view returns (uint256) {
        uint256 mintedSoFar = nextTokenIdToMint - 1;
        return totalToMint - mintedSoFar;
    }

    function _padded(uint256 id) internal pure returns (string memory) {
        // Zero-pad to 3 digits for ids 1..999 (001..999). Revert if out of range
        require(id > 0 && id <= 999, "id out of range");
        bytes memory s = new bytes(3);

        if (id < 10) {
            s[0] = 0x30; // '0'
            s[1] = 0x30; // '0'
            s[2] = bytes1(uint8(0x30 + id));
        } else if (id < 100) {
            uint256 tens = id / 10;
            uint256 ones = id - tens * 10;
            s[0] = 0x30; // '0'
            s[1] = bytes1(uint8(0x30 + tens));
            s[2] = bytes1(uint8(0x30 + ones));
        } else {
            // 100..999
            uint256 hundreds = id / 100;
            uint256 remainder = id - hundreds * 100;
            uint256 tens = remainder / 10;
            uint256 ones = remainder - tens * 10;
            s[0] = bytes1(uint8(0x30 + hundreds));
            s[1] = bytes1(uint8(0x30 + tens));
            s[2] = bytes1(uint8(0x30 + ones));
        }
        return string(s);
    }
}


