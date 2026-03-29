// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

interface IUniswapV2Router02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract MainnetForkTest is Test {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function testReadUsdcTotalSupply() public {
        string memory rpcUrl = "https://eth-mainnet.g.alchemy.com/v2/EvFBdMbJCSYm_Ir1fwhzC";
        if (bytes(rpcUrl).length == 0) {
            return;
        }

        vm.createSelectFork(rpcUrl);

        uint256 totalSupply = IERC20(USDC).totalSupply();
        assertGt(totalSupply, 1_000_000e6);
    }

    function testSimulateUniswapV2SwapOnFork() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            return;
        }

        vm.createSelectFork(rpcUrl);

        uint256 amountIn = 1_000e6;
        deal(USDC, address(this), amountIn);

        IERC20(USDC).approve(UNISWAP_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        uint256[] memory quoted = IUniswapV2Router02(UNISWAP_V2_ROUTER).getAmountsOut(amountIn, path);
        uint256 minAmountOut = (quoted[1] * 99) / 100;

        uint256 wethBefore = IERC20(WETH).balanceOf(address(this));

        uint256[] memory amounts = IUniswapV2Router02(UNISWAP_V2_ROUTER)
            .swapExactTokensForTokens(amountIn, minAmountOut, path, address(this), block.timestamp + 1 hours);

        assertEq(amounts[0], amountIn);
        assertGt(amounts[1], 0);
        assertEq(IERC20(WETH).balanceOf(address(this)), wethBefore + amounts[1]);
    }

    function testRollForkAdvancesBlockNumber() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            return;
        }

        vm.createSelectFork(rpcUrl);

        uint256 startingBlock = block.number;
        vm.rollFork(startingBlock + 5);

        assertEq(block.number, startingBlock + 5);
    }
}
