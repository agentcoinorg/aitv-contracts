// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import {DecentralizedAutonomousTrust} from "@fairmint/contracts/DecentralizedAutonomousTrust.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";

contract AgentKey is DecentralizedAutonomousTrust {
    bool public isStopped;

    constructor(
        uint256 _initReserve,
        address _currencyAddress,
        uint256 _initGoal,
        uint256 _buySlopeNum,
        uint256 _buySlopeDen,
        uint256 _investmentReserveBasisPoints,
        uint256 _setupFee,
        address payable _setupFeeRecipient,
        string memory _name,
        string memory _symbol
    ) public {
        initialize(
            _initReserve,
            _currencyAddress,
            _initGoal,
            _buySlopeNum,
            _buySlopeDen,
            _investmentReserveBasisPoints,
            _setupFee,
            _setupFeeRecipient,
            _name,
            _symbol
        );
    }

    /// @notice Stops the contract and transfers the reserve to the recipient. To be used in case of a migration to a new contract.
    function stopAndTransferReserve(address payable _recipient) external {
        require(msg.sender == beneficiary, "BENEFICIARY_ONLY");
        isStopped = true;
        Address.sendValue(_recipient, address(this).balance);
    }

    /// @dev Overrides the modifier in ContinuousOffering
    modifier authorizeTransfer(address _from, address _to, uint256 _value, bool _isSell) {
        if (isStopped) {
            revert("Contract is stopped");
        }
        if (address(whitelist) != address(0)) {
            // This is not set for the minting of initialReserve
            whitelist.authorizeTransfer(_from, _to, _value, _isSell);
        }
        _;
    }
}
