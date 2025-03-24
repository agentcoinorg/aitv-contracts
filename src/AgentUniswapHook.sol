// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseHookUpgradeable} from "./BaseHookUpgradeable.sol";
import {IFeeSetter} from "./interfaces/IFeeSetter.sol";
import {IAuthorizeLaunchPool} from "./interfaces/IAuthorizeLaunchPool.sol";
import {UniswapFeeInfo} from "./types/UniswapFeeInfo.sol";
import {IBurnable} from "./interfaces/IBurnable.sol";

/// @title Agent Uniswap Hook
/// @notice A hook contract for Uniswap V4 that takes fees and burns agent tokens on swaps
contract AgentUniswapHook is Ownable2StepUpgradeable, UUPSUpgradeable, BaseHookUpgradeable, IFeeSetter, IAuthorizeLaunchPool {
    error OnlyLaunchPool();
    error OnlyOwnerOrController();
    error InvalidCollateral();
    error ZeroAddressNotAllowed();

    event SetController(address controller);
    event SetFeesForPair(address token1, address token2, UniswapFeeInfo uniswapFeeInfo);
    event SetAuthorizedLaunchPool(address launchPool, bool authorized);

    IPoolManager public poolManager;
    address public controller;
    mapping(bytes32 => UniswapFeeInfo) public fees;
    mapping(address => bool) public authorizedLaunchPools;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the owner, controller, and Uniswap pool manager
    /// @param _owner The owner of the contract, can upgrade the contract and set the controller
    /// @param _controller The controller of the contract, can set fees for pairs and authorize launch pools (normally this is the AgentFactory contract)
    /// @param _uniswapPoolManager The Uniswap pool manager contract
    function initialize(
        address _owner,
        address _controller,
        address _uniswapPoolManager
    ) external initializer {
        // _controller not checked for zero address because we can set it later
        if (_uniswapPoolManager == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        __Ownable_init(_owner); // Checks for zero address
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        poolManager = IPoolManager(_uniswapPoolManager);
        controller = _controller;
        validateHookAddress(this);
    }

    /// @notice Sets the controller of the contract
    /// @dev Controller should be the AgentFactory contract
    /// @param _controller The new controller of the contract
    function setController(address _controller) external virtual onlyOwner {
        controller = _controller;

        emit SetController(_controller);
    }

    /// @notice Sets the fees for a pair of tokens
    /// @param _tokenA The address of the first token
    /// @param _tokenB The address of the second token
    /// @param _uniswapFeeInfo The fee information for the pair
    function setFeesForPair(address _tokenA, address _tokenB, UniswapFeeInfo calldata _uniswapFeeInfo) external virtual {
        if (msg.sender != owner() && msg.sender != controller) {
            revert OnlyOwnerOrController();
        }

        if (_tokenA != _uniswapFeeInfo.collateral && _tokenB != _uniswapFeeInfo.collateral) {
            revert InvalidCollateral();
        }

        address currency0 = _tokenA < _tokenB ? _tokenA : _tokenB;
        address currency1 = _tokenA < _tokenB ? _tokenB : _tokenA;

        bytes32 key = keccak256(abi.encodePacked(currency0, currency1));

        fees[key] = _uniswapFeeInfo;

        emit SetFeesForPair(currency0, currency1, _uniswapFeeInfo);
    }

    /// @notice Sets whether a launch pool is authorized to use this hook
    /// @dev This protects the hook from being used by other Uniswap pools
    /// @param launchPool The address of the launch pool
    /// @param authorized Whether the launch pool is authorized
    function setAuthorizedLaunchPool(address launchPool, bool authorized) external virtual {
        if (msg.sender != owner() && msg.sender != controller) {
            revert OnlyOwnerOrController();
        }

        if (authorized) {
            authorizedLaunchPools[launchPool] = true;
        } else {
            delete authorizedLaunchPools[launchPool];
        }

        emit SetAuthorizedLaunchPool(launchPool, authorized);
    }

    /// @notice Getter for fees
    /// @dev The token addresses do not need to be sorted, the function will sort them
    /// @param _tokenA The address of the first token
    /// @param _tokenB The address of the second token
    /// @return The fees for the pair
    function getFeesForPair(address _tokenA, address _tokenB) external view returns (UniswapFeeInfo memory) {
        address currency0 = _tokenA < _tokenB ? _tokenA : _tokenB;
        address currency1 = _tokenA < _tokenB ? _tokenB : _tokenA;

        return _getFeesForPair(currency0, currency1);
    }

    /// @notice Returns the permissions for the hook
    /// @dev This is used to validate the hook address during deployment
    /// We use all permissions so that we can upgrade the hook in the future
    /// @return The permissions for the hook
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: true,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: true,
            afterDonate: true,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: true,
            afterRemoveLiquidityReturnDelta: true
        });
    }

    /// @notice Returns the fees for a pair of tokens
    /// @param currency0 The address of the first token
    /// @param currency1 The address of the second token
    /// @return The fees for the pair
    function _getFeesForPair(address currency0, address currency1) internal view virtual returns (UniswapFeeInfo memory) {
        bytes32 key = keccak256(abi.encodePacked(currency0, currency1));
        return fees[key];
    }

    /// @notice Returns the pool manager
    /// @return The pool manager
    function _getPoolManager() internal view virtual override returns (IPoolManager) {
        return poolManager;
    }

    /// @notice Access control to upgrade the contract
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    /// @notice Before initialize hook
    /// @dev Only authorized launch pools can use this hook
    /// This prevents the hook from being used by other Uniswap pools
    /// @param sender The sender of the transaction
    function _beforeInitialize(address sender, PoolKey calldata, uint160) internal virtual override returns (bytes4) {
        if (!authorizedLaunchPools[sender]) {
            revert OnlyLaunchPool();
        }

        return BaseHookUpgradeable.beforeInitialize.selector;
    }

    /// @notice Before swap hook, sends fees to recipients and takes agent tokens to be burned in the after swap hook
    /// @param _key The pool key
    /// @param _params The swap parameters
    /// @dev Fee is taken from collateral and agent tokens are taken to be burned after the swap
    /// If collateral amount is known, then collateral fee is taken and no agent tokens are burned
    /// If the agent token amount is known, then the agent token fee is burned and collateral is not taken
    function _beforeSwap(
        address,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata _params,
        bytes calldata
    ) internal virtual override returns (bytes4, BeforeSwapDelta, uint24) {
        uint256 swapAmount = _params.amountSpecified < 0
            ? uint256(-_params.amountSpecified)
            : uint256(_params.amountSpecified);

        UniswapFeeInfo memory pairFees = _getFeesForPair(Currency.unwrap(_key.currency0), Currency.unwrap(_key.currency1));

        Currency collateralCurrency = pairFees.collateral == Currency.unwrap(_key.currency0) ? _key.currency0 : _key.currency1;
        Currency agentCurrency = pairFees.collateral == Currency.unwrap(_key.currency0) ? _key.currency1 : _key.currency0;

        bool isBuyAgent = _params.zeroForOne 
            ? _key.currency0 == collateralCurrency
            : _key.currency1 == collateralCurrency;

        uint256 totalFee;

        // If buying the agent token and output amount is specified, take the burn fee
        // If selling the agent token and input amount is specified, take the burn fee
        // Otherwise, take the fee for the specified recipients
        if ((isBuyAgent && _params.amountSpecified > 0) || (!isBuyAgent && _params.amountSpecified < 0)) {
            totalFee = swapAmount * pairFees.burnBasisAmount / 1e4;
            poolManager.take(agentCurrency, address(this), totalFee);
        } else {
            totalFee = takeFees(swapAmount, collateralCurrency, pairFees);
        }

        return (BaseHookUpgradeable.beforeSwap.selector, toBeforeSwapDelta(int128(int256(totalFee)), 0), 0);
    }

    /// @notice Takes fees for a swap
    /// @param swapAmount The amount of the swap
    /// @param currency The currency of the fees
    /// @param pairFees The fees for the pair
    /// @return totalFee The total fee taken
    function takeFees(uint256 swapAmount, Currency currency, UniswapFeeInfo memory pairFees) internal virtual returns (uint256 totalFee) {
        uint256 length = pairFees.recipients.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 fee = swapAmount * pairFees.basisAmounts[i] / 1e4;
            totalFee += fee;
            poolManager.take(currency, pairFees.recipients[i], fee);
        }

        return totalFee;
    }

    function _afterInitialize(address, PoolKey calldata, uint160, int24) internal virtual override returns (bytes4) {
        return BaseHookUpgradeable.afterInitialize.selector;
    }

    function _beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        return BaseHookUpgradeable.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) internal virtual override returns (bytes4) {
        return BaseHookUpgradeable.beforeRemoveLiquidity.selector;
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        return (BaseHookUpgradeable.afterAddLiquidity.selector, toBalanceDelta(0, 0));
    }

    function _afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        return (BaseHookUpgradeable.afterRemoveLiquidity.selector, toBalanceDelta(0, 0));
    }

    /// @notice Before swap hook
    /// @param _key The pool key
    /// @dev If the hook has agent tokens, burn them
    function _afterSwap(address, PoolKey calldata _key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        virtual
        override
        returns (bytes4, int128)
    {
        address token0 = Currency.unwrap(_key.currency0);
        address token1 = Currency.unwrap(_key.currency1);

        UniswapFeeInfo memory pairFees = _getFeesForPair(token0, token1);

        // Currency 0 is collateral, currency 1 is agent token, burn currency 1
        if (token0 == pairFees.collateral) {
            uint256 balance1 = IERC20(token1).balanceOf(address(this));

            if (balance1 > 0) {
                IBurnable(token1).burn(balance1);
            }
        } else { // Currency 1 is collateral, currency 0 is agent token, burn currency 0
            uint256 balance0 = IERC20(token0).balanceOf(address(this));

            if (balance0 > 0) {
                IBurnable(token0).burn(balance0);
            }
        }

        return (BaseHookUpgradeable.afterSwap.selector, 0);
    }

    function _beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        internal
        virtual
        override
        returns (bytes4)
    {
        return BaseHookUpgradeable.beforeDonate.selector;
    }

    function _afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) internal virtual override
        returns (bytes4)
    {
        return BaseHookUpgradeable.afterDonate.selector;
    }
}
