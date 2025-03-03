// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AgentToken} from "./AgentToken.sol";
import {AirdropClaim} from "./AirdropClaim.sol";
import {IAgentKey} from "./IAgentKey.sol";
import {AgentStaking} from "./AgentStaking.sol";

/// @title AgentLaunchPool
/// @notice The following is a contract to launch Agent Tokens
/// The contract will:
/// - Allow users to deposit ETH to receive Agent Tokens after the launch 
/// On launch it will:
/// - Deploy the Agent Token contract
/// - Deploy the Agent Token Staking contract
/// - Allow users to claim their tokens
/// - Create and fund a liquidity pool on Uniswap
/// - Distribute tokens to the specified recipients and the pool
/// If the launch fails, users can reclaim their deposits
contract AgentLaunchPool {
    using SafeERC20 for IERC20;

    error AlreadyDeployed();
    error NoCollateralToDeploy();
    error NotEnoughTokensToDeploy();
    error AlreadyLaunched();
    error LengthMismatch();
    error TimeWindowNotPassed();
    error DepositsClosed();
    error NotLaunched();
    error MinAmountNotReached();
    error MinAmountReached();
    error NotDeposited();
    error MaxAmountReached();
    error InvalidCollateral();

    event LiquidityPoolCreated(address pair);
    event Claim(address indexed recipient, address claimer, uint256 ethDeposited, uint256 amountClaimed);
    event Deposit(address indexed beneficiary, address indexed depositor, uint256 amount);
    event ReclaimDeposits(address indexed sender, uint256 amount);

    struct TokenMetadata {
        address owner;
        string name;
        string symbol;
    }

    IUniswapV2Router02 public immutable uniswapRouter;

    string public tokenName;
    string public tokenSymbol;
    IERC20 public immutable collateralToken;
    address public immutable owner;
    uint256 public immutable timeWindow;
    uint256 public immutable minAmountForLaunch;
    uint256 public immutable maxAmountForLaunch;
    uint256 public immutable launchPoolAmount;
    uint256 public immutable uniswapPoolAmount;
    address[] public recipients;
    uint256[] public amounts; 

    bool public hasLaunched;
    uint256 public launchPoolCreatedOn;
    uint256 public totalDeposited;
    address public agentToken;
    address public agentStaking;
    mapping(address => uint256) public deposits;

    constructor(
        TokenMetadata memory _agentTokenMetadata,
        uint256 _timeWindow,
        uint256 _minAmountForLaunch,
        uint256 _maxAmountForLaunch,
        address _collateralToken,
        uint256 _launchPoolAmount, 
        uint256 _uniswapPoolAmount, 
        address _uniswapRouter,
        address[] memory _recipients,
        uint256[] memory _amounts
    ) {
        owner = _agentTokenMetadata.owner;
        tokenName = _agentTokenMetadata.name;
        tokenSymbol = _agentTokenMetadata.symbol;
        timeWindow = _timeWindow;
        minAmountForLaunch = _minAmountForLaunch;
        maxAmountForLaunch = _maxAmountForLaunch;
        collateralToken = IERC20(_collateralToken);
        launchPoolAmount = _launchPoolAmount;
        uniswapPoolAmount = _uniswapPoolAmount;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);

        if (_recipients.length != _amounts.length) {
            revert LengthMismatch();
        }

        recipients = _recipients;
        amounts = _amounts;

        launchPoolCreatedOn = block.timestamp;
    }

    /// @notice Launch the Agent Token
    /// The contract will deploy the Agent Token contract, create a liquidity pool on Uniswap and deploy the staking contract
    /// Users that have deposited ETH can claim their agent tokens after the launch
    function launch() external {
        if (hasLaunched) {
            revert AlreadyLaunched();
        }

        if (!_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        if (totalDeposited < minAmountForLaunch) {
            revert MinAmountNotReached();
        }

        hasLaunched = true;

        address contractOwner = owner;

        // Deploy the agent token contract
        address agentTokenAddress = _deployAgentToken(contractOwner);

        _deployAgentStaking(contractOwner, agentTokenAddress);

        // Deploy the ETH from launch pool and a portion of the tokens to the Uniswap pair to create liquidity
        _addLiquidity(agentTokenAddress);
    }

    /// @notice Deposit ETH collateral to receive Agent Tokens after the launch
    function depositETH() external payable {
        depositETHFor(msg.sender);
    }

    // @notice Deposit ERC20 collateral to receive Agent Tokens after the launch
    /// @param amount The amount of tokens to deposit
    function depositERC20(uint256 amount) external {
        depositERC20For(msg.sender, amount);
    }

    /// @notice Check if the user can deposit collateral    
    function canDeposit() external view returns (bool) {
        return !hasLaunched && !_hasTimeWindowPassed();
    }

    /// @notice Claim tokens for multiple recipients
    /// @param _recipients The addresses of the recipients
    function multiClaim(address[] calldata _recipients) external {
        if (!hasLaunched) {
            revert NotLaunched();
        }

        for (uint256 i = 0; i < _recipients.length; i++) {
            _claim(_recipients[i]);
        }
    }

    /// @notice Deposit ETH for the beneficiary to receive Agent Tokens after the launch
    /// @param beneficiary The address of the beneficiary
    function depositETHFor(address beneficiary) public payable {
        if (address(collateralToken) != address(0)) {
            revert InvalidCollateral();
        }

        if (hasLaunched || _hasTimeWindowPassed()) {
            revert DepositsClosed();
        }

        if (totalDeposited + msg.value > maxAmountForLaunch) {
            revert MaxAmountReached();
        }

        totalDeposited += msg.value;
        deposits[beneficiary] += msg.value;

        emit Deposit(beneficiary, msg.sender, msg.value);
    }

    /// @notice Deposit ERC20 for the beneficiary to receive Agent Tokens after the launch
    /// @param beneficiary The address of the beneficiary
    /// @param amount The amount of tokens to deposit
    function depositERC20For(address beneficiary, uint256 amount) public {
        if (address(collateralToken) == address(0)) {
            revert InvalidCollateral();
        }

        if (hasLaunched || _hasTimeWindowPassed()) {
            revert DepositsClosed();
        }

        if (totalDeposited + amount > maxAmountForLaunch) {
            revert MaxAmountReached();
        }

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);

        totalDeposited += amount;
        deposits[beneficiary] += amount;

        emit Deposit(beneficiary, msg.sender, amount);
    }

    /// @notice Reclaim deposits if the launch has failed
    /// The launch has failed if the time window has passed and the minimum amount has not been reached
    function reclaimDeposits() external {
        if (!_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        if (totalDeposited >= minAmountForLaunch) {
            revert MinAmountReached();
        }

        if (deposits[msg.sender] == 0) {
            revert NotDeposited();
        }

        uint256 amount = deposits[msg.sender];
        deposits[msg.sender] = 0;

        if (address(collateralToken) == address(0)) {
            payable(msg.sender).call{value: amount}("");
        } else {
            collateralToken.safeTransfer(msg.sender, amount);
        }

        emit ReclaimDeposits(msg.sender, amount);
    }

    /// @notice Claim tokens for the recipient that will be transferred from the contract to the recipient
    /// @param _recipient The address of the recipient
    /// @return If the claim was successful or not
    function claim(address _recipient) public returns (bool) {
        if (!hasLaunched) {
            revert NotLaunched();
        }

        return _claim(_recipient);
    }

    /// @notice Check if the recipient can claim tokens
    /// @param _recipient The address of the recipient
    function canClaim(address _recipient) public view returns (bool) {
        return hasLaunched && deposits[_recipient] > 0;
    }

    /// @notice Claim tokens for the recipient that will be transferred from the contract to the recipient
    /// @param _recipient The address of the recipient
    /// @return If the claim was successful or not
    function _claim(address _recipient) internal returns (bool) {
        if (deposits[_recipient] == 0) {
            return false;
        }

        uint256 ethDeposited = deposits[_recipient];

        if (ethDeposited == 0) {
            return false;
        }

        uint256 amountToTransfer = launchPoolAmount * ethDeposited / totalDeposited;

        deposits[_recipient] = 0;
        IERC20(agentToken).safeTransfer(_recipient, amountToTransfer);

        emit Claim(_recipient, msg.sender, ethDeposited, amountToTransfer);

        return true;
    }

    /// @notice Deploys the agent token contract and initializes it
    /// @param _owner The owner of the agent token
    /// @return The address of the deployed contract
    function _deployAgentToken(address _owner) internal returns (address) {
        if (agentToken != address(0)) {
            revert AlreadyDeployed();
        }

        // Deploy the implementation contract
        AgentToken implementation = new AgentToken();

        address[] memory airdropRecipients = new address[](recipients.length + 1);
        airdropRecipients[0] = address(this);
        for (uint256 i = 0; i < recipients.length; i++) {
            airdropRecipients[i + 1] = recipients[i];
        }

        uint256[] memory airdropAmounts = new uint256[](recipients.length + 1);
        airdropAmounts[0] = launchPoolAmount + uniswapPoolAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            airdropAmounts[i + 1] = amounts[i];
        }

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentToken.initialize, (tokenName, tokenSymbol, _owner, airdropRecipients, airdropAmounts))
        );

        agentToken = address(proxy);

        return address(proxy);
    }

    /// @notice Deploys the agent token staking contract and initializes it
    /// @param _owner The owner of the staking contract
    /// @param _agentTokenAddress The address of the agent token
    function _deployAgentStaking(address _owner, address _agentTokenAddress) internal {
        if (agentStaking != address(0)) {
            revert AlreadyDeployed();
        }

        // Deploy the implementation contract
        AgentStaking implementation = new AgentStaking();

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentStaking.initialize, (_owner, _agentTokenAddress))
        );

        agentStaking = address(proxy);
    }

    /// @notice Adds liquidity to the Uniswap pair
    /// The contract must have the agent tokens and ETH in its balance
    /// @param _agentTokenAddress The address of the agent token
    /// @dev We burn the LP tokens by sending them to the 0 address
    function _addLiquidity(address _agentTokenAddress) internal {
        uint256 tokenBalance = IERC20(_agentTokenAddress).balanceOf(address(this));
        uint256 collateralBalance = address(collateralToken) == address(0)
            ? address(this).balance
            : collateralToken.balanceOf(address(this));
        
        if (tokenBalance < launchPoolAmount + uniswapPoolAmount) {
            revert NotEnoughTokensToDeploy();
        }

        if (collateralBalance == 0) {
            revert NoCollateralToDeploy();
        }

        IERC20(_agentTokenAddress).approve(address(uniswapRouter), uniswapPoolAmount);

        if (address(collateralToken) == address(0)) {
            uniswapRouter.addLiquidityETH{value: collateralBalance}(
                _agentTokenAddress,             // Agent token address
                uniswapPoolAmount,               // All ERC20 tokens held by the contract
                uniswapPoolAmount * 995 / 1000,  // Min of 99.5% of the agent tokens will be added to the pool
                collateralBalance * 995 / 1000,  // Min of 99.5% of the collateral will be added to the pool
                address(0),                      // NULL address receives the LP tokens
                block.timestamp                  // Deadline
            );
        } else {
            collateralToken.approve(address(uniswapRouter), collateralBalance);

            uniswapRouter.addLiquidity(
                _agentTokenAddress,             // Agent token address
                address(collateralToken),        // Collateral token address
                uniswapPoolAmount,               // All ERC20 tokens held by the contract
                collateralBalance,               // All ETH held by the contract
                uniswapPoolAmount * 995 / 1000,  // Min of 99.5% of the agent tokens will be added to the pool
                collateralBalance * 995 / 1000,  // Min of 99.5% of the collateral will be added to the pool
                address(0),                      // NULL address receives the LP tokens
                block.timestamp                  // Deadline
            );
        }
    }

    /// @notice Check if the time window has passed
    /// The time window is the time that users have to deposit ETH before the launch
    /// After the time window has passed, the launch can be initiated
    /// @return If the time window has passed
    function _hasTimeWindowPassed() internal view returns (bool) {
        return launchPoolCreatedOn + timeWindow <= block.timestamp;
    }

    /// @notice Fallback function to deposit ETH
    receive() external payable {
        depositETHFor(msg.sender);
    }
}