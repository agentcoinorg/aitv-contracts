// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20VotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AgentKeyV2} from "./AgentKeyV2.sol";
import {AirdropClaim} from "./AirdropClaim.sol";

/// @title GECKO v2 Token
/// @notice The following is a version 2 ERC20 token contract for the gecko keys
/// @dev It is upgradable and has snapshot functionality
contract GeckoKeyV2 is AgentKeyV2 {
    function initialize(string calldata name, string calldata symbol, address owner, address[] calldata recipients, address[] calldata amounts, address geckoV1TokenAddress, uint256 airdropAmount) public override initializer {
        super.initialize(owner, recipients, amounts);

        AirdropClaim airdrop = new AirdropClaim(
            address(geckoV1TokenAddress),
            address(this),
            airdropAmount
        );

        _mint(address(airdrop), airdropAmount);
    }
}
