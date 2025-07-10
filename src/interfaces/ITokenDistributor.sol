pragma solidity ^0.8.0;

interface ITokenDistributor {
    function distributeETH(
        bytes32 _distributionName, 
        address _beneficiary,
        address _recipientOnFailure,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline
    ) external payable;

    function distributeERC20(
        bytes32 _distributionName, 
        address _beneficiary, 
        uint256 _amount, 
        address _paymentToken,
        address _recipientOnFailure,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline
    ) external;
}
