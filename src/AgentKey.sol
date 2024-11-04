// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import {DecentralizedAutonomousTrust} from "@fairmint/contracts/DecentralizedAutonomousTrust.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";

contract AgentKey is DecentralizedAutonomousTrust {
    bool public isStopped;

    constructor(
        uint _initReserve,
        address _currencyAddress,
        uint _initGoal,
        uint _buySlopeNum,
        uint _buySlopeDen,
        uint _investmentReserveBasisPoints,
        uint _setupFee,
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

    function stopAndTransferReserve(address payable _recipient) external {
        require(msg.sender == beneficiary, "BENEFICIARY_ONLY");
        isStopped = true;
        Address.sendValue(_recipient, address(this).balance);
    }

    modifier authorizeTransfer(
        address _from,
        address _to,
        uint _value,
        bool _isSell
    ) // Overrides the modifier in ContinuousOffering
    {
        if (isStopped) {
            revert("Contract is stopped");
        }
        if(address(whitelist) != address(0))
        {
            // This is not set for the minting of initialReserve
            whitelist.authorizeTransfer(_from, _to, _value, _isSell);
        }
        _;
    }
}
