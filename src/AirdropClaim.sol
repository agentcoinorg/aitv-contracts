// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

contract AirdropClaim {
    using SafeERC20 for IERC20;

    event Claim(address indexed recipient, address claimer, uint256 fromBalance, uint256 amountClaimed);

    IERC20 public fromToken;
    IERC20 public toToken;

    uint256 public totalDeposited;

    mapping(address => bool) public claimed;

    constructor(
        address _fromToken,
        address _toToken,
        uint256 _totalDeposited
    ) public {
        fromToken = IERC20(_fromToken);
        toToken = IERC20(_toToken);
        totalDeposited = _totalDeposited;
    }

    function claim(address _recipient) external returns (bool) {
        if (claimed[_recipient]) {
            return false;
        }
        uint256 balance = fromToken.balanceOf(_recipient);

        uint256 ratio = balance / fromToken.totalSupply();
        uint256 amountToTransfer = totalDeposited * ratio;

        claimed[_recipient] = true;
        toToken.safeTransfer(_recipient, amountToTransfer);

        emit Claim(_recipient, msg.sender, balance, amountToTransfer);

        return true;
    }

    function multiClaim(address[] calldata _recipients) external {
        for (uint256 i = 0; i < _recipients.length; i++) {
            claim(_recipients[i]);
        }
    }
}
