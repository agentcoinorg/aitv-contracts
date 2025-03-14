// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
 
import {IAgentToken} from "./interfaces/IAgentToken.sol";
import {IAgentStaking} from "./interfaces/IAgentStaking.sol";
import {IAgentLaunchPool} from "./interfaces/IAgentLaunchPool.sol";
import {TokenInfo} from "./types/TokenInfo.sol";
import {LaunchPoolInfo} from "./types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "./types/UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "./types/AgentDistributionInfo.sol";
import {UniswapPoolDeployer} from "./UniswapPoolDeployer.sol";

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
contract AgentLaunchPool is UniswapPoolDeployer, OwnableUpgradeable, UUPSUpgradeable, IAgentLaunchPool {
    using SafeERC20 for IERC20;

    error AlreadyDeployed();
    error NotEnoughCollateralToDeploy();
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
    event Claim(address indexed recipient, address claimer, uint256 deposit, uint256 amountClaimed);
    event Deposit(address indexed beneficiary, address indexed depositor, uint256 amount);
    event ReclaimDeposits(address indexed sender, uint256 amount);

    TokenInfo public tokenInfo;
    LaunchPoolInfo public launchPoolInfo;
    UniswapPoolInfo public uniswapPoolInfo;
    AgentDistributionInfo public distributionInfo;
    IPoolManager public uniswapPoolManager;
    IPositionManager public uniswapPositionManager;

    bool public hasLaunched;
    uint256 public launchPoolCreatedOn;
    uint256 public totalDeposited;
    address public agentToken;
    address public agentStaking;
    mapping(address => uint256) public deposits;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        IPoolManager _uniswapPoolManager,
        IPositionManager _uniswapPositionManager
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();

        if (_launchPoolInfo.collateralRecipients.length != _launchPoolInfo.collateralBasisAmounts.length) {
            revert LengthMismatch();
        }

        if (_distributionInfo.recipients.length != _distributionInfo.basisAmounts.length) {
            revert LengthMismatch();
        }

        tokenInfo = _tokenInfo;
        launchPoolInfo = _launchPoolInfo;
        uniswapPoolInfo = _uniswapPoolInfo;
        distributionInfo = _distributionInfo;
        uniswapPoolManager = _uniswapPoolManager;
        uniswapPositionManager = _uniswapPositionManager;

        launchPoolCreatedOn = block.timestamp;
    }

    /// @notice Launch the Agent Token
    /// The contract will deploy the Agent Token contract, create a liquidity pool on Uniswap and deploy the staking contract
    /// Users that have deposited ETH can claim their agent tokens after the launch
    function launch() external virtual {
        if (hasLaunched) {
            revert AlreadyLaunched();
        }

        if (!_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        if (totalDeposited < launchPoolInfo.minAmountForLaunch) {
            revert MinAmountNotReached();
        }

        hasLaunched = true;

        address contractOwner = tokenInfo.owner;

        // Deploy the agent token contract
        address agentTokenAddress = _deployAgentToken(contractOwner);

        _deployAgentStaking(contractOwner, agentTokenAddress);

        _distributeCollateral();

        _setupInitialLiquidity(launchPoolInfo.collateral, agentTokenAddress);
    }

    function computeAgentTokenAddress() external virtual returns(address) {
        if (agentToken != address(0)) {
            return agentToken;
        }

        uint256 length = distributionInfo.recipients.length; // This is the same as the length of basisAmounts because of the check in the constructor

        address[] memory airdropRecipients = new address[](length + 1);
        airdropRecipients[0] = address(this);
        for (uint256 i = 0; i < length; i++) {
            airdropRecipients[i + 1] = distributionInfo.recipients[i];
        }

        uint256[] memory airdropAmounts = new uint256[](length + 1);
        airdropAmounts[0] = (distributionInfo.launchPoolBasisAmount + distributionInfo.uniswapPoolBasisAmount) * tokenInfo.totalSupply / 10000;
        for (uint256 i = 0; i < length; i++) {
            airdropAmounts[i + 1] = distributionInfo.basisAmounts[i] * tokenInfo.totalSupply / 10000;
        }

        bytes memory tokenCtorArgs = abi.encodeCall(IAgentToken.initialize, (tokenInfo.name, tokenInfo.symbol, tokenInfo.owner, airdropRecipients, airdropAmounts));
        bytes memory proxyCtorArgs = abi.encode(tokenInfo.tokenImplementation, tokenCtorArgs);

        return computeCreate2Address(address(this), bytes32(0), type(ERC1967Proxy).creationCode, proxyCtorArgs);
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
        if (launchPoolInfo.collateral != address(0)) {
            revert InvalidCollateral();
        }

        if (hasLaunched || _hasTimeWindowPassed()) {
            revert DepositsClosed();
        }

        if (totalDeposited >= launchPoolInfo.maxAmountForLaunch) {
            revert MaxAmountReached();
        }

        uint256 maxAmountDepositable = launchPoolInfo.maxAmountForLaunch - totalDeposited;
        uint256 depositAmount = msg.value > maxAmountDepositable ? maxAmountDepositable : msg.value;

        totalDeposited += depositAmount;
        deposits[beneficiary] += depositAmount;

        if (depositAmount < msg.value) {
            payable(beneficiary).call{value: msg.value - depositAmount}("");
        }

        emit Deposit(beneficiary, msg.sender, depositAmount);
    }

    /// @notice Deposit ERC20 for the beneficiary to receive Agent Tokens after the launch
    /// @param beneficiary The address of the beneficiary
    /// @param amount The amount of tokens to deposit
    function depositERC20For(address beneficiary, uint256 amount) public {
        if (launchPoolInfo.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (hasLaunched || _hasTimeWindowPassed()) {
            revert DepositsClosed();
        }

        if (totalDeposited >= launchPoolInfo.maxAmountForLaunch) {
            revert MaxAmountReached();
        }

        uint256 maxAmountDepositable = launchPoolInfo.maxAmountForLaunch - totalDeposited;
        uint256 depositAmount = amount > maxAmountDepositable ? maxAmountDepositable : amount;

        IERC20(launchPoolInfo.collateral).safeTransferFrom(msg.sender, address(this), depositAmount);

        totalDeposited += depositAmount;
        deposits[beneficiary] += depositAmount;

        emit Deposit(beneficiary, msg.sender, depositAmount);
    }

    /// @notice Reclaim ETH deposits if the launch has failed
    /// The launch has failed if the time window has passed and the minimum amount has not been reached
    function reclaimETHDepositsFor(address payable beneficiary) external {
        if (launchPoolInfo.collateral != address(0)) {
            revert InvalidCollateral();
        }

        if (!_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        if (totalDeposited >= launchPoolInfo.minAmountForLaunch) {
            revert MinAmountReached();
        }

        if (deposits[beneficiary] == 0) {
            revert NotDeposited();
        }

        uint256 amount = deposits[beneficiary];
        deposits[beneficiary] = 0;

        beneficiary.call{value: amount}("");

        emit ReclaimDeposits(beneficiary, amount);
    }

    /// @notice Reclaim ERC20 deposits if the launch has failed
    /// The launch has failed if the time window has passed and the minimum amount has not been reached
    function reclaimERC20DepositsFor(address beneficiary) external {
        if (launchPoolInfo.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (!_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        if (totalDeposited >= launchPoolInfo.minAmountForLaunch) {
            revert MinAmountReached();
        }

        if (deposits[beneficiary] == 0) {
            revert NotDeposited();
        }

        uint256 amount = deposits[beneficiary];
        deposits[beneficiary] = 0;

   
        IERC20(launchPoolInfo.collateral).safeTransfer(beneficiary, amount);

        emit ReclaimDeposits(beneficiary, amount);
    }

    /// @notice Fallback function to deposit ETH
    receive() external payable {
        depositETHFor(msg.sender);
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
    function _claim(address _recipient) internal virtual returns (bool) {
        if (deposits[_recipient] == 0) {
            return false;
        }

        uint256 deposit = deposits[_recipient];

        if (deposit == 0) {
            return false;
        }

        uint256 amountToTransfer = (distributionInfo.launchPoolBasisAmount * tokenInfo.totalSupply / 10000) * deposit / totalDeposited;

        deposits[_recipient] = 0;
        IERC20(agentToken).safeTransfer(_recipient, amountToTransfer);

        emit Claim(_recipient, msg.sender, deposit, amountToTransfer);

        return true;
    }

    /// @notice Deploys the agent token contract and initializes it
    /// @param _owner The owner of the agent token
    /// @return The address of the deployed contract
    function _deployAgentToken(address _owner) internal returns (address) {
        if (agentToken != address(0)) {
            revert AlreadyDeployed();
        }

        uint256 length = distributionInfo.recipients.length; // This is the same as the length of basisAmounts because of the check in the constructor

        address[] memory airdropRecipients = new address[](length + 1);
        airdropRecipients[0] = address(this);
        for (uint256 i = 0; i < length; i++) {
            airdropRecipients[i + 1] = distributionInfo.recipients[i];
        }

        uint256[] memory airdropAmounts = new uint256[](length + 1);
        airdropAmounts[0] = (distributionInfo.launchPoolBasisAmount + distributionInfo.uniswapPoolBasisAmount) * tokenInfo.totalSupply / 1e4;
        for (uint256 i = 0; i < length; i++) {
            airdropAmounts[i + 1] = distributionInfo.basisAmounts[i] * tokenInfo.totalSupply / 1e4;
        }

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy{salt: bytes32(0)}(
            tokenInfo.tokenImplementation, abi.encodeCall(IAgentToken.initialize, (tokenInfo.name, tokenInfo.symbol, _owner, airdropRecipients, airdropAmounts))
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

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(tokenInfo.stakingImplementation), abi.encodeCall(IAgentStaking.initialize, (_owner, _agentTokenAddress))
        );

        agentStaking = address(proxy);
    }

    /// @notice Adds liquidity to the Uniswap pair
    /// The contract must have the agent tokens and ETH in its balance
    /// @param _agentTokenAddress The address of the agent token
    /// @dev We burn the LP tokens by sending them to the 0 address
    function _setupInitialLiquidity(address _collateral, address _agentTokenAddress) internal virtual {
        uint256 launchPoolAmount = distributionInfo.launchPoolBasisAmount * tokenInfo.totalSupply / 1e4;
        uint256 uniswapPoolAmount = distributionInfo.uniswapPoolBasisAmount * tokenInfo.totalSupply / 1e4;

        uint256 tokenBalance = IERC20(_agentTokenAddress).balanceOf(address(this));
        uint256 collateralBalance = _collateral == address(0)
            ? address(this).balance
            : IERC20(_collateral).balanceOf(address(this));
        
        if (tokenBalance < launchPoolAmount + uniswapPoolAmount) {
            revert NotEnoughTokensToDeploy();
        }

        uint256 requiredCollateralAmount = launchPoolInfo.collateralUniswapPoolBasisAmount * totalDeposited / 1e4;

        if (collateralBalance < requiredCollateralAmount) {
            revert NotEnoughCollateralToDeploy();
        }

        _createPoolAndAddLiquidity(
            PoolInfo({
                poolManager: uniswapPoolManager,
                positionManager: uniswapPositionManager,
                collateral: _collateral,
                agentToken: _agentTokenAddress,
                collateralAmount: requiredCollateralAmount,
                agentTokenAmount: uniswapPoolAmount,
                lpRecipient: uniswapPoolInfo.lpRecipient,
                lpFee: uniswapPoolInfo.lpFee,
                tickSpacing: uniswapPoolInfo.tickSpacing,
                startingPrice: _calculateUniswapStartingPrice(
                    _collateral,
                    _agentTokenAddress,
                    requiredCollateralAmount,  // We use the total collateral deposited and launchPoolAmount (agent tokens) since we want to starting price 
                    uniswapPoolAmount // to be the same as what the launch pool depositors bought in for
                ),
                hook: uniswapPoolInfo.hook,
                permit2: uniswapPoolInfo.permit2
            })
        );
    }

    function _distributeCollateral() internal virtual {
        uint256 length = launchPoolInfo.collateralRecipients.length;

        if (launchPoolInfo.collateral == address(0)) {
            for (uint256 i = 0; i < length; i++) {
                uint256 amount = launchPoolInfo.collateralBasisAmounts[i] * totalDeposited / 1e4;
                payable(launchPoolInfo.collateralRecipients[i]).call{value: amount}("");
            }
        } else {
            for (uint256 i = 0; i < length; i++) {
                uint256 amount = launchPoolInfo.collateralBasisAmounts[i] * totalDeposited / 1e4;
                IERC20(launchPoolInfo.collateral).safeTransfer(launchPoolInfo.collateralRecipients[i], amount);
            }
        }
    }

    /// @notice Check if the time window has passed
    /// The time window is the time that users have to deposit ETH before the launch
    /// After the time window has passed, the launch can be initiated
    /// @return If the time window has passed
    function _hasTimeWindowPassed() internal view returns (bool) {
        return launchPoolCreatedOn + launchPoolInfo.timeWindow <= block.timestamp;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function _calculateUniswapStartingPrice(
        address _collateral,
        address _agentToken,
        uint256 _collateralAmount,
        uint256 _agentAmount
    ) internal pure returns (uint160) {
        uint256 currency0Amount = _collateral < _agentToken ? _collateralAmount : _agentAmount;
        uint256 currency1Amount = _collateral < _agentToken ? _agentAmount : _collateralAmount;

        uint256 ratio = (currency1Amount * 1e18) / currency0Amount; // Multiply by 1e18 for precision
        uint256 sqrtRatio = Math.sqrt(ratio); // Take square root
        
        uint256 startingPrice = (sqrtRatio * (2**96)) / 1e9; // Scale back to maintain precision

        return uint160(startingPrice);
    }

    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes memory bytecode,
        bytes memory constructorArgs
    ) internal pure virtual returns (address) {
        // Append constructor arguments to bytecode
        bytes memory initCode = abi.encodePacked(bytecode, constructorArgs);

        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xFF),
            deployer,
            salt,
            keccak256(initCode)
        )))));
    }
}