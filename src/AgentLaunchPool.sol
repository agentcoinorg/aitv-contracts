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
import {DistributionAndPriceChecker} from "./DistributionAndPriceChecker.sol";

/// @title AgentLaunchPool
/// @notice The following is a contract to launch Agent Tokens
/// The contract will:
/// - Allow users to deposit ETH to receive Agent Tokens after the launch 
/// On launch it will:
/// - Deploy the Agent Token contract
/// - Deploy the Agent Token Staking contract
/// - Allow users to claim their agent tokens
/// - Create and fund a liquidity pool on Uniswap V4
/// - Distribute agent tokens to the specified recipients (this happens as part of Agent Token deployment) and the pool
/// - Distribute collateral to the specified recipients
/// If the launch fails, users can reclaim their deposits
contract AgentLaunchPool is UniswapPoolDeployer, DistributionAndPriceChecker, OwnableUpgradeable, UUPSUpgradeable, IAgentLaunchPool {
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

    event Launch(address agentToken, address agentStaking);
    event Claim(address indexed recipient, address indexed claimer, uint256 deposit, uint256 amountClaimed);
    event Deposit(address indexed beneficiary, address indexed depositor, uint256 amount);
    event ReclaimDeposits(address indexed beneficiary, address indexed sender, uint256 amount);

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

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract and the one who can upgrade it
    /// @param _tokenInfo Information about the token
    /// @param _launchPoolInfo Information about the launch pool
    /// @param _uniswapPoolInfo Information about the Uniswap pool
    /// @param _distributionInfo Information about the distribution
    /// @param _uniswapPoolManager The address of the Uniswap pool manager
    /// @param _uniswapPositionManager The address of the position manager
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

        _requireCorrectDistribution(_launchPoolInfo, _distributionInfo);

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
    /// @dev Anyone can call this function, but it can only be called once
    function launch() external virtual {
        if (hasLaunched) {
            revert AlreadyLaunched();
        }

        if (totalDeposited < launchPoolInfo.minAmountForLaunch) {
            revert MinAmountNotReached();
        }

        if (totalDeposited < launchPoolInfo.maxAmountForLaunch && !_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        hasLaunched = true;

        address contractOwner = tokenInfo.owner;

        // Deploy the agent token contract
        address agentTokenAddress = _deployAgentToken(contractOwner);

        _deployAgentStaking(contractOwner, agentTokenAddress);

        _distributeCollateral();

        _setupInitialLiquidity(launchPoolInfo.collateral, agentTokenAddress);

        emit Launch(agentTokenAddress, agentStaking);
    }

    /// @notice Compute the address of the agent token contract that will be deployed
    /// @dev This is necessary to set the fees in the uniswap hook
    function computeAgentTokenAddress() external virtual view returns(address) {
        if (agentToken != address(0)) {
            return agentToken;
        }
        
        bytes memory tokenCtorArgs = _getAgentTokenCtorArgs(tokenInfo.owner);
        bytes memory proxyCtorArgs = abi.encode(tokenInfo.tokenImplementation, tokenCtorArgs);

        return computeCreate2Address(address(this), bytes32(0), type(ERC1967Proxy).creationCode, proxyCtorArgs);
    }

    /// @notice Deposit ETH collateral to receive Agent Tokens after the launch
    /// @dev Can only be called if the pool is using ETH collateral
    function depositETH() external payable virtual {
        depositETHFor(msg.sender);
    }

    /// @notice Deposit ERC20 collateral to receive Agent Tokens after the launch
    /// @dev Can only be called if the pool is using ERC20 collateral
    /// @param _amount The amount of tokens to deposit
    function depositERC20(uint256 _amount) external virtual {
        depositERC20For(msg.sender, _amount);
    }

    /// @notice Claim tokens for multiple recipients
    /// @param _recipients The addresses of the recipients
    function multiClaim(address[] calldata _recipients) external virtual {
        if (!hasLaunched) {
            revert NotLaunched();
        }

        for (uint256 i = 0; i < _recipients.length; i++) {
            _claim(_recipients[i]);
        }
    }

    /// @notice Deposit ETH for the beneficiary to receive Agent Tokens after the launch
    /// @dev Can only be called if the pool is using ETH collateral
    /// @param _beneficiary The address of the beneficiary
    function depositETHFor(address _beneficiary) public payable virtual {
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
        deposits[_beneficiary] += depositAmount;

        // Refund the user if they sent more than the max amount
        if (depositAmount < msg.value) {
            payable(_beneficiary).call{value: msg.value - depositAmount}(""); 
        }

        emit Deposit(_beneficiary, msg.sender, depositAmount);
    }

    /// @notice Deposit ERC20 for the beneficiary to receive Agent Tokens after the launch
    /// @dev Can only be called if the pool is using ERC20 collateral
    /// @param _beneficiary The address of the beneficiary
    /// @param _amount The amount of tokens to deposit
    function depositERC20For(address _beneficiary, uint256 _amount) public virtual {
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
        uint256 depositAmount = _amount > maxAmountDepositable ? maxAmountDepositable : _amount;

        IERC20(launchPoolInfo.collateral).safeTransferFrom(msg.sender, address(this), depositAmount);

        totalDeposited += depositAmount;
        deposits[_beneficiary] += depositAmount;

        emit Deposit(_beneficiary, msg.sender, depositAmount);
    }

    /// @notice Reclaim ETH deposits if the launch has failed
    /// The launch has failed if the time window has passed and the minimum amount has not been reached
    /// @dev Can only be called if the pool is using ETH collateral
    /// @param _beneficiary The address of the beneficiary
    /// @return If the reclaim was successful or not
    function reclaimETHDepositsFor(address payable _beneficiary) external virtual returns(bool) {
        if (launchPoolInfo.collateral != address(0)) {
            revert InvalidCollateral();
        }

        if (!_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        if (totalDeposited >= launchPoolInfo.minAmountForLaunch) {
            revert MinAmountReached();
        }

        if (deposits[_beneficiary] == 0) {
            return false;
        }

        uint256 amount = deposits[_beneficiary];
        deposits[_beneficiary] = 0;

        _beneficiary.call{value: amount}("");

        emit ReclaimDeposits(_beneficiary, msg.sender, amount);

        return true;
    }

    /// @notice Reclaim ERC20 deposits if the launch has failed
    /// The launch has failed if the time window has passed and the minimum amount has not been reached
    /// @dev Can only be called if the pool is using ERC20 collateral
    /// @param _beneficiary The address of the beneficiary
    /// @return If the reclaim was successful or not
    function reclaimERC20DepositsFor(address _beneficiary) external virtual returns(bool) {
        if (launchPoolInfo.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (!_hasTimeWindowPassed()) {
            revert TimeWindowNotPassed();
        }

        if (totalDeposited >= launchPoolInfo.minAmountForLaunch) {
            revert MinAmountReached();
        }

        if (deposits[_beneficiary] == 0) {
            return false;
        }

        uint256 amount = deposits[_beneficiary];
        deposits[_beneficiary] = 0;

        IERC20(launchPoolInfo.collateral).safeTransfer(_beneficiary, amount);

        emit ReclaimDeposits(_beneficiary, msg.sender, amount);

        return true;
    }

    /// @notice Fallback function to deposit ETH
    receive() external payable {
        depositETHFor(msg.sender);
    }

    /// @notice Getter for token info
    /// @return The token info
    function getTokenInfo() external virtual view returns (TokenInfo memory) {
        return tokenInfo;
    }

    /// @notice Getter for launch pool info
    /// @return The launch pool info
    function getLaunchPoolInfo() external virtual view returns (LaunchPoolInfo memory) {
        return launchPoolInfo;
    }

    /// @notice Getter for uniswap pool info
    /// @return The uniswap pool info
    function getUniswapPoolInfo() external virtual view returns (UniswapPoolInfo memory) {
        return uniswapPoolInfo;
    }

    /// @notice Getter for distribution info
    /// @return The distribution info
    function getDistributionInfo() external virtual view returns (AgentDistributionInfo memory) {
        return distributionInfo;
    }

    /// @notice Claim tokens for the recipient that will be transferred from the contract to the recipient
    /// @param _recipient The address of the recipient
    /// @return If the claim was successful or not
    function claim(address _recipient) public virtual returns (bool) {
        if (!hasLaunched) {
            revert NotLaunched();
        }

        return _claim(_recipient);
    }

    /// @notice Check if the recipient can claim tokens
    /// @param _recipient The address of the recipient
    function canClaim(address _recipient) public virtual view returns (bool) {
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

        uint256 amountToTransfer = (distributionInfo.launchPoolBasisAmount * tokenInfo.totalSupply / 1e4) * deposit / totalDeposited;

        deposits[_recipient] = 0;
        IERC20(agentToken).safeTransfer(_recipient, amountToTransfer);

        emit Claim(_recipient, msg.sender, deposit, amountToTransfer);

        return true;
    }

    /// @notice Deploys the agent token contract and initializes it
    /// @param _owner The owner of the agent token
    /// @return The address of the deployed contract
    function _deployAgentToken(address _owner) internal virtual returns (address) {
        if (agentToken != address(0)) {
            revert AlreadyDeployed();
        }

        bytes memory tokenCtorArgs = _getAgentTokenCtorArgs(_owner);

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy{salt: bytes32(0)}(tokenInfo.tokenImplementation, tokenCtorArgs);

        agentToken = address(proxy);

        return address(proxy);
    }

    /// @notice Deploys the agent token staking contract and initializes it
    /// @param _owner The owner of the staking contract
    /// @param _agentTokenAddress The address of the agent token
    function _deployAgentStaking(address _owner, address _agentTokenAddress) internal virtual {
        if (agentStaking != address(0)) {
            revert AlreadyDeployed();
        }

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(tokenInfo.stakingImplementation), abi.encodeCall(IAgentStaking.initialize, (_owner, _agentTokenAddress))
        );

        agentStaking = address(proxy);
    }

    /// @notice Creates the Uniswap pool and adds initial liquidity
    /// The contract must have the agent tokens and ETH in its balance
    /// @param _collateral The address of the collateral token
    /// @param _agentTokenAddress The address of the agent token
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
                    requiredCollateralAmount,
                    uniswapPoolAmount
                ),
                hook: uniswapPoolInfo.hook,
                permit2: uniswapPoolInfo.permit2
            })
        );
    }

    /// @notice Distribute the collateral to the recipients
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
    /// The time window is the time that users have to deposit collateral before the launch
    /// After the time window has passed, the launch can be initiated
    /// @return If the time window has passed
    function _hasTimeWindowPassed() internal virtual view returns (bool) {
        return launchPoolCreatedOn + launchPoolInfo.timeWindow <= block.timestamp;
    }

    /// @notice Access control to upgrade the contract
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    /// @notice Get the constructor arguments for the agent token contract
    /// @dev This is re-used between the compute address and deploy agent token functions        
    /// @param _owner The owner of the agent token
    function _getAgentTokenCtorArgs(address _owner) internal virtual view returns (bytes memory) {
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

        bytes memory tokenCtorArgs = abi.encodeCall(IAgentToken.initialize, (tokenInfo.name, tokenInfo.symbol, _owner, airdropRecipients, airdropAmounts));

        return tokenCtorArgs;
    }

    /// @notice Calculate the starting price for the Uniswap pool
    /// The price of the agent token on the Uniswap pool should be higher or equal to the price that the depositors got in for
    /// @param _collateral The address of the collateral token
    /// @param _agentToken The address of the agent token
    /// @param _collateralAmount The amount of collateral
    /// @param _agentAmount The amount of agent tokens
    function _calculateUniswapStartingPrice(
        address _collateral,
        address _agentToken,
        uint256 _collateralAmount,
        uint256 _agentAmount
    ) internal virtual pure returns (uint160) {
        uint256 currency0Amount = _collateral < _agentToken ? _collateralAmount : _agentAmount;
        uint256 currency1Amount = _collateral < _agentToken ? _agentAmount : _collateralAmount;

        uint256 ratio = (currency1Amount * 1e18) / currency0Amount; // Multiply by 1e18 for precision
        uint256 sqrtRatio = Math.sqrt(ratio); // Take square root
        
        uint256 startingPrice = (sqrtRatio * (2**96)) / 1e9; // Scale back to maintain precision

        return uint160(startingPrice);
    }

    /// @notice Utility function to compute create2 addresses
    /// @dev This is used to predict the agent token address
    /// @param deployer The address of the deployer
    /// @param salt The salt
    /// @param bytecode The bytecode of the contract
    /// @param constructorArgs The constructor arguments
    /// @return The computed address
    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes memory bytecode,
        bytes memory constructorArgs
    ) internal virtual pure returns (address) {
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