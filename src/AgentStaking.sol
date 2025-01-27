// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract AgentStaking is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    
    error EmptyAmount();
    error InsufficientStakedBalance();
    error NoLockedWithdrawalsFound();

    IERC20 public agentToken;
    uint256 public constant UNLOCK_TIME = 1 days;

    struct LockedWithdrawal {
        uint256 amount;
        uint256 lockedUntil;
    }

    mapping(address => uint256) private stakes;
    mapping(address => LockedWithdrawal[]) private lockedWithdrawals;
    mapping(address => uint256) private lockedWithdrawalStartIndexes;

    event Stake(address indexed account, uint256 amount, uint256 totalStaked);
    event Unstake(address indexed account, uint256 amount, uint256 unlockTime, uint256 totalStaked);
    event Claim(address indexed account, uint256 amount, address recipient);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _agentToken) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();

        agentToken = IERC20(_agentToken);
    }

    function stake(uint256 amount) external {
        if (amount == 0) {
            revert EmptyAmount();
        }

        agentToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 totalStaked = stakes[msg.sender] + amount;
        stakes[msg.sender] = totalStaked;
        emit Stake(msg.sender, amount, totalStaked);
    }

    function unstake(uint256 amount) external {
        if (amount == 0) {
            revert EmptyAmount();
        }

        if (amount > stakes[msg.sender]) {
            revert InsufficientStakedBalance();
        }

        uint256 totalStaked = stakes[msg.sender] - amount; 
        stakes[msg.sender] = totalStaked;

        lockedWithdrawals[msg.sender].push(LockedWithdrawal(amount, block.timestamp + UNLOCK_TIME));
        emit Unstake(msg.sender, amount, block.timestamp + UNLOCK_TIME, totalStaked);
    }

    function claim(uint256 count, address recipient) external {
        uint256 start = lockedWithdrawalStartIndexes[msg.sender];

        uint256 length = lockedWithdrawals[msg.sender].length;

        if (start >= length) {
            revert NoLockedWithdrawalsFound();
        }

        uint256 end = start + count > length ? length : start + count;

        uint256 amountToTransfer = 0;
        for (; start < end; start++) {
            if (lockedWithdrawals[msg.sender][start].amount == 0) {
                revert EmptyAmount();
            }
            if (block.timestamp < lockedWithdrawals[msg.sender][start].lockedUntil) {
                break;
            }
            amountToTransfer += lockedWithdrawals[msg.sender][start].amount;
            delete lockedWithdrawals[msg.sender][start];
        }

        if (amountToTransfer > 0) {
            lockedWithdrawalStartIndexes[msg.sender] = start;
            agentToken.safeTransfer(recipient, amountToTransfer);

            emit Claim(msg.sender, amountToTransfer, recipient);
        }
    }

    function getStakedAmount(address account) external view returns (uint256) {
        return stakes[account];
    }

    function getWithdrawals(address account, uint256 start, uint256 count) external view returns (LockedWithdrawal[] memory) {
        start = lockedWithdrawalStartIndexes[account] + start;
        uint256 length = lockedWithdrawals[account].length;

        if (start >= length) {
            return new LockedWithdrawal[](0);
        }

        uint256 end = start + count > length ? length : start + count;

        count = end - start;

        LockedWithdrawal[] memory result = new LockedWithdrawal[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = lockedWithdrawals[account][start + i];
        }

        return result;
    }

    function getWithdrawalCount(address account) external view returns (uint256) {
        return lockedWithdrawals[account].length - lockedWithdrawalStartIndexes[account];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
