// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20VotesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title Agent token contract
/// @notice The following is an ERC20 token contract for the agent tokens
/// @dev It is upgradable and has snapshot functionality
contract AgentToken is ERC20VotesUpgradeable, OwnableUpgradeable, ERC20BurnableUpgradeable, UUPSUpgradeable {
    error LengthMismatch();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name, string memory symbol, address owner, address[] calldata recipients, uint256[] calldata amounts) external initializer {
        __ERC20_init(name, symbol);
        __ERC20Votes_init();
        __ERC20Burnable_init();
        __Ownable_init(owner);
        __UUPSUpgradeable_init();

        if (recipients.length != amounts.length) {
            revert LengthMismatch();
        }

        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {} 
}
