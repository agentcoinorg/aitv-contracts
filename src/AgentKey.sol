// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.5.17;

import {DecentralizedAutonomousTrust} from "@fairmint/contracts/DecentralizedAutonomousTrust.sol";

contract AgentKey is DecentralizedAutonomousTrust {
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
}
