// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from '@uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';¸
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {SafeCast} from '@uniswap/v4-core/src/libraries/SafeCast.sol';
import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AirdropClaim} from "../src/AirdropClaim.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";

contract UniswapV4Test is Test {
    address owner = makeAddr("owner");
    address uniswapPoolManager;
    address uniswapPositionManager;
    address agentWallet = makeAddr("agentWallet");
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        uniswapPoolManager = vm.envAddress("BASE_POOL_MANAGER");
        uniswapPositionManager = vm.envAddress("BASE_POSITION_MANAGER");
    }

    function test_aa() public {
        MockedERC20 memecoin = new MockedERC20();

        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG
        );

        bytes memory constructorArgs = abi.encode(uniswapPoolManager, uniswapPositionManager, address(0), address(memecoin));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(MyHooks).creationCode, constructorArgs);

        MyHooks hooks = new MyHooks{salt: salt}(
            uniswapPoolManager, 
            uniswapPositionManager,
            address(0),
            address(memecoin)
        );

        require(address(hooks) == hookAddress, "Hook address mismatch");

        vm.deal(address(this), 2000 ether);
        memecoin.mint(address(hooks), 1000 * 1e18);

        uint256 tokenAAmount = 100 ether;
        uint256 tokenBAmount = 100 * 1e18;

        hooks.createPoolAndAddLiquidity{value: tokenAAmount}(tokenAAmount, tokenBAmount);

        uint256 ethBalance = address(hooks).balance;
        uint256 memecoinBalance = memecoin.balanceOf(address(hooks));

        console.logUint(ethBalance);
        console.logUint(memecoinBalance);
    }
}

contract MyHooks is BaseHook {
    uint256 private startFee0;
    uint256 private startFee1;

    using SafeERC20 for IERC20;
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    error CannotBeInitializedDirectly();

    IPositionManager positionManager;
    address tokenA;
    address tokenB;

    constructor(address _poolManager, address _positionManager, address _tokenA, address _tokenB) BaseHook(IPoolManager(_poolManager)) {
        positionManager = IPositionManager(_positionManager);
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function createPoolAndAddLiquidity(uint256 tokenAAmount, uint256 tokenBAmount) external payable {
        uint24 lpFee = 10000; // 1%
        int24 tickSpacing = 200;
        address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        uint256 amountAMax = tokenAAmount;
        uint256 amountBMax = tokenBAmount;

        // Provide full-range liquidity to the pool
        int24 tickLower = TickMath.minUsableTick(tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(tickSpacing);

        uint256 liquidity = LiquidityAmounts
            .getLiquidityForAmounts(
                SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                amountAMax,
                amountBMax
            );

        bool isNativeA = tokenA == address(0);

        uint256 startingPrice = 1 * 2**96; // 1:1 ratio of tokenA:tokenB

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(tokenA < tokenB ? tokenA : tokenB),
            currency1: Currency.wrap(tokenA < tokenB ? tokenB : tokenA),
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(this))
        });

        bytes[] memory params = new bytes[](2);
        
        // Step 1: Initialize the Pool
        params[0] = abi.encodeWithSelector(
            positionManager.initializePool.selector,
            pool,
            startingPrice
        );

        // Step 2: Prepare liquidity modification commands
        bytes memory actions = abi.encodePacked(uint8(0x02), uint8(0x0d)); // MINT_POSITION, SETTLE_PAIR

        // int24 tickLower = -tickSpacing * 10;
        // int24 tickUpper = tickSpacing * 10;

        bytes[] memory mintParams = new bytes[](2);
        mintParams[0] = abi.encode(
            pool,
            tickLower,
            tickUpper,
            liquidity,
            amountAMax,
            amountBMax,
            address(this),
            ""
        );
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);

        uint256 deadline = block.timestamp + 60;
        params[1] = abi.encodeWithSelector(
            IPositionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            deadline
        );

        // Approve ERC20 transfers via Permit2
        if (!isNativeA) {
            IERC20(tokenA).approve(address(permit2), type(uint256).max);
            IAllowanceTransfer(permit2).approve(tokenA, address(positionManager), type(uint160).max, type(uint48).max);
        }

        IERC20(tokenB).approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(permit2).approve(tokenB, address(positionManager), type(uint160).max, type(uint48).max);

        // Execute the transaction
        if (isNativeA) {
            positionManager.multicall{value: msg.value}(params);
        } else {
            positionManager.multicall(params);
        }
    }

    /**
     * The hook called before the state of a pool is initialized. Prevents external contracts
     * from initializing pools using our contract as a hook.
     *
     * @dev As we call `poolManager.initialize` from the IHooks contract itself, we bypass this
     * hook call as therefore bypass the prevention.
     */
    function _beforeInitialize(address, PoolKey calldata, uint160) internal view override returns (bytes4) {
        revert CannotBeInitializedDirectly();
    }

    function _beforeSwap(
        address _sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata _params,
        bytes calldata _hookData
    ) internal override returns (bytes4, int128) {
        if (params.zeroForOne) {
            startFee0 = poolManager.hookFeesAccrued(address(key.hooks), key.currency0);
        } else {
            startFee1 = poolManager.hookFeesAccrued(address(key.hooks), key.currency1);
        }

        return (BaseHook.beforeSwap.selector, 0);
    }

    function _afterSwap(
        address _sender,
        PoolKey calldata _key,
        IPoolManager.SwapParams calldata _params,
        BalanceDelta _delta,
        bytes calldata _hookData
    ) internal override returns (bytes4, int128) {
        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * Defines the Uniswap V4 hooks that are used by our implementation. This will determine
     * the address that our contract **must** be deployed to for Uniswap V4. This address suffix
     * is shown in the dev comments for this function call.
     *
     * @dev 1011 1111 0111 00 == 2FDC
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}

contract MockedERC20 is MockERC20 {
    constructor() {
        initialize("MockedERC20", "MERC", 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}