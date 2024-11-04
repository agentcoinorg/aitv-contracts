// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IAgentKey {
    function approve(address spender, uint256 amount) external returns (bool);
    function buy(address _to, uint256 _currencyValue, uint256 _minTokensBought) external payable;
    function sell(address payable _to, uint256 _quantityToSell, uint256 _minCurrencyReturned) external;
    function estimateBuyValue(uint256 _currencyValue) external view returns (uint256);
    function estimateSellValue(uint256 _quantityToSell) external view returns (uint256);
    function balanceOf(address _owner) external view returns (uint256);
    function state() external view returns (uint256);
    function updateConfig(
        address _whitelistAddress,
        address payable _beneficiary,
        address _control,
        address payable _feeCollector,
        uint256 _feeBasisPoints,
        uint256 _revenueCommitmentBasisPoints,
        uint256 _minInvestment,
        uint256 _minDuration
    ) external;
    function pay(uint256 _currencyValue) external payable;
    function totalSupply() external view returns (uint256);
    function buybackReserve() external view returns (uint256);
    function feeBasisPoints() external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function close() external;
    function stopAndTransferReserve(address payable _recipient) external;
    function isStopped() external view returns (bool);
}
