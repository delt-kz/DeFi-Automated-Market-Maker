// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AMM} from "../../src/AMM.sol";
import {LPToken} from "../../src/LPToken.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract AMMTest is Test {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    AMM internal amm;
    LPToken internal lpToken;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        amm = new AMM(address(tokenA), address(tokenB), "AMM LP", "ALP");
        lpToken = amm.lpToken();

        tokenA.mint(alice, 10_000 ether);
        tokenB.mint(alice, 10_000 ether);
        tokenA.mint(bob, 10_000 ether);
        tokenB.mint(bob, 10_000 ether);
        tokenA.mint(carol, 10_000 ether);
        tokenB.mint(carol, 10_000 ether);

        vm.prank(alice);
        tokenA.approve(address(amm), type(uint256).max);
        vm.prank(alice);
        tokenB.approve(address(amm), type(uint256).max);
        vm.prank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        vm.prank(bob);
        tokenB.approve(address(amm), type(uint256).max);
        vm.prank(carol);
        tokenA.approve(address(amm), type(uint256).max);
        vm.prank(carol);
        tokenB.approve(address(amm), type(uint256).max);
    }

    function testInitialAddLiquidity() public {
        vm.prank(alice);
        (uint256 amount0, uint256 amount1, uint256 liquidity) = amm.addLiquidity(100 ether, 400 ether, 200 ether);

        assertEq(amount0, 100 ether);
        assertEq(amount1, 400 ether);
        assertEq(liquidity, 200 ether);
        assertEq(lpToken.balanceOf(alice), 200 ether);
        assertEq(tokenA.balanceOf(address(amm)), 100 ether);
        assertEq(tokenB.balanceOf(address(amm)), 400 ether);
    }

    function testInitialAddLiquidityRevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.addLiquidity(100 ether, 0, 1);
    }

    function testInitialAddLiquidityRevertsWhenMinimumLiquidityTooHigh() public {
        vm.prank(alice);
        vm.expectRevert(AMM.InsufficientLiquidityMinted.selector);
        amm.addLiquidity(100 ether, 400 ether, 201 ether);
    }

    function testSubsequentAddLiquidityUsesOptimalRatio() public {
        vm.prank(alice);
        amm.addLiquidity(100 ether, 100 ether, 100 ether);

        uint256 bobABefore = tokenA.balanceOf(bob);
        uint256 bobBBefore = tokenB.balanceOf(bob);

        vm.prank(bob);
        (uint256 amount0, uint256 amount1, uint256 liquidity) = amm.addLiquidity(50 ether, 80 ether, 50 ether);

        assertEq(amount0, 50 ether);
        assertEq(amount1, 50 ether);
        assertEq(liquidity, 50 ether);
        assertEq(tokenA.balanceOf(bob), bobABefore - 50 ether);
        assertEq(tokenB.balanceOf(bob), bobBBefore - 50 ether);
        assertEq(lpToken.balanceOf(bob), 50 ether);
    }

    function testSubsequentAddLiquidityMintsProportionalLpTokens() public {
        vm.prank(alice);
        amm.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether);

        vm.prank(bob);
        (,, uint256 liquidity) = amm.addLiquidity(500 ether, 500 ether, 500 ether);

        assertEq(liquidity, 500 ether);
        assertEq(lpToken.totalSupply(), 1_500 ether);
    }

    function testRemovePartialLiquidity() public {
        vm.prank(alice);
        amm.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether);

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = amm.removeLiquidity(400 ether, 400 ether, 400 ether);

        assertEq(amount0, 400 ether);
        assertEq(amount1, 400 ether);
        assertEq(lpToken.balanceOf(alice), 600 ether);
        assertEq(tokenA.balanceOf(address(amm)), 600 ether);
        assertEq(tokenB.balanceOf(address(amm)), 600 ether);
    }

    function testRemoveFullLiquidity() public {
        vm.prank(alice);
        amm.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether);

        vm.prank(alice);
        amm.removeLiquidity(1_000 ether, 1_000 ether, 1_000 ether);

        assertEq(lpToken.totalSupply(), 0);
        assertEq(tokenA.balanceOf(address(amm)), 0);
        assertEq(tokenB.balanceOf(address(amm)), 0);
    }

    function testRemoveLiquidityRevertsOnZeroLiquidity() public {
        vm.prank(alice);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.removeLiquidity(0, 0, 0);
    }

    function testRemoveLiquidityRevertsWhenMinAmountsAreTooHigh() public {
        vm.prank(alice);
        amm.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether);

        vm.prank(alice);
        vm.expectRevert(AMM.InsufficientLiquidityBurned.selector);
        amm.removeLiquidity(500 ether, 600 ether, 600 ether);
    }

    function testSwapTokenAToTokenB() public {
        _seedPool();

        uint256 expectedOut = amm.getAmountOut(100 ether, 1_000 ether, 1_000 ether);

        vm.prank(bob);
        uint256 amountOut = amm.swap(address(tokenA), 100 ether, expectedOut, bob);

        assertEq(amountOut, expectedOut);
        assertEq(tokenB.balanceOf(bob), 10_000 ether + expectedOut);
        assertEq(tokenA.balanceOf(address(amm)), 1_100 ether);
        assertEq(tokenB.balanceOf(address(amm)), 1_000 ether - expectedOut);
    }

    function testSwapTokenBToTokenA() public {
        _seedPool();

        uint256 expectedOut = amm.getAmountOut(100 ether, 1_000 ether, 1_000 ether);

        vm.prank(bob);
        uint256 amountOut = amm.swap(address(tokenB), 100 ether, expectedOut, bob);

        assertEq(amountOut, expectedOut);
        assertEq(tokenA.balanceOf(bob), 10_000 ether + expectedOut);
        assertEq(tokenB.balanceOf(address(amm)), 1_100 ether);
        assertEq(tokenA.balanceOf(address(amm)), 1_000 ether - expectedOut);
    }

    function testSwapRevertsOnInvalidToken() public {
        _seedPool();
        MockERC20 fakeToken = new MockERC20("Fake", "FAK", 18);
        fakeToken.mint(bob, 1_000 ether);

        vm.prank(bob);
        fakeToken.approve(address(amm), type(uint256).max);

        vm.prank(bob);
        vm.expectRevert(AMM.InvalidToken.selector);
        amm.swap(address(fakeToken), 1 ether, 0, bob);
    }

    function testSwapRevertsOnZeroAmount() public {
        _seedPool();

        vm.prank(bob);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.swap(address(tokenA), 0, 0, bob);
    }

    function testSwapRevertsOnSlippageProtection() public {
        _seedPool();

        uint256 expectedOut = amm.getAmountOut(100 ether, 1_000 ether, 1_000 ether);

        vm.prank(bob);
        vm.expectRevert(AMM.InsufficientOutputAmount.selector);
        amm.swap(address(tokenA), 100 ether, expectedOut + 1, bob);
    }

    function testKDoesNotDecreaseAfterSwap() public {
        _seedPool();
        uint256 kBefore = tokenA.balanceOf(address(amm)) * tokenB.balanceOf(address(amm));

        vm.prank(bob);
        amm.swap(address(tokenA), 100 ether, 0, bob);

        uint256 kAfter = tokenA.balanceOf(address(amm)) * tokenB.balanceOf(address(amm));
        assertGe(kAfter, kBefore);
    }

    function testLargeSwapHasHigherPriceImpactThanSmallSwap() public {
        _seedPool();

        uint256 smallOut = amm.getAmountOut(10 ether, 1_000 ether, 1_000 ether);
        uint256 largeOut = amm.getAmountOut(400 ether, 1_000 ether, 1_000 ether);

        assertLt(largeOut * 10, smallOut * 400);
    }

    function testSwapToAnotherReceiver() public {
        _seedPool();
        uint256 expectedOut = amm.getAmountOut(100 ether, 1_000 ether, 1_000 ether);

        vm.prank(bob);
        amm.swap(address(tokenA), 100 ether, expectedOut, carol);

        assertEq(tokenB.balanceOf(carol), 10_000 ether + expectedOut);
    }

    function testFuzzSwapTokenAToTokenB(uint256 amountIn) public {
        _seedPool();

        uint256 boundedAmount = bound(amountIn, 1 ether, 300 ether);
        uint256 reserveBeforeA = tokenA.balanceOf(address(amm));
        uint256 reserveBeforeB = tokenB.balanceOf(address(amm));
        uint256 expectedOut = amm.getAmountOut(boundedAmount, reserveBeforeA, reserveBeforeB);

        vm.prank(bob);
        uint256 amountOut = amm.swap(address(tokenA), boundedAmount, 0, bob);

        assertEq(amountOut, expectedOut);
        assertEq(tokenA.balanceOf(address(amm)), reserveBeforeA + boundedAmount);
        assertEq(tokenB.balanceOf(address(amm)), reserveBeforeB - amountOut);
    }

    function _seedPool() internal {
        vm.prank(alice);
        amm.addLiquidity(1_000 ether, 1_000 ether, 1_000 ether);
    }
}
