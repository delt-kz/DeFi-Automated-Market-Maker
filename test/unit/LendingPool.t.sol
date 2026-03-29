// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../../src/LendingPool.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../../src/mocks/MockPriceOracle.sol";

contract LendingPoolTest is Test {
    MockERC20 internal collateralToken;
    MockERC20 internal debtToken;
    MockPriceOracle internal oracle;
    LendingPool internal pool;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal liquidator = makeAddr("liquidator");

    function setUp() public {
        collateralToken = new MockERC20("Collateral", "COL", 18);
        debtToken = new MockERC20("Debt", "DEBT", 18);
        oracle = new MockPriceOracle(2e18);
        pool = new LendingPool(address(collateralToken), address(debtToken), address(oracle), 1e15);

        collateralToken.mint(alice, 1_000 ether);
        collateralToken.mint(bob, 1_000 ether);
        collateralToken.mint(liquidator, 1_000 ether);
        debtToken.mint(address(pool), 1_000_000 ether);
        debtToken.mint(alice, 1_000 ether);
        debtToken.mint(liquidator, 1_000 ether);

        vm.prank(alice);
        collateralToken.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        debtToken.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        collateralToken.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        debtToken.approve(address(pool), type(uint256).max);
        vm.prank(liquidator);
        collateralToken.approve(address(pool), type(uint256).max);
        vm.prank(liquidator);
        debtToken.approve(address(pool), type(uint256).max);
    }

    function testDepositStoresCollateral() public {
        vm.prank(alice);
        pool.deposit(100 ether);

        (uint256 deposited, uint256 borrowed,) = pool.getUserPosition(alice);
        assertEq(deposited, 100 ether);
        assertEq(borrowed, 0);
        assertEq(collateralToken.balanceOf(address(pool)), 100 ether);
    }

    function testWithdrawWithoutDebt() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.withdraw(40 ether);
        vm.stopPrank();

        (uint256 deposited,,) = pool.getUserPosition(alice);
        assertEq(deposited, 60 ether);
        assertEq(collateralToken.balanceOf(alice), 940 ether);
    }

    function testBorrowWithinLtv() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(100 ether);
        vm.stopPrank();

        (, uint256 borrowed, uint256 hf) = pool.getUserPosition(alice);
        assertEq(borrowed, 100 ether);
        assertGt(hf, 1e18);
        assertEq(debtToken.balanceOf(alice), 1_100 ether);
    }

    function testBorrowExceedingLtvReverts() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        vm.expectRevert(LendingPool.ExceedsMaxLtv.selector);
        pool.borrow(151 ether);
        vm.stopPrank();
    }

    function testRepayPartial() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(100 ether);
        pool.repay(30 ether);
        vm.stopPrank();

        (, uint256 borrowed,) = pool.getUserPosition(alice);
        assertEq(borrowed, 70 ether);
    }

    function testRepayFullWithLargerAmountCapsAtDebt() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(100 ether);
        uint256 paid = pool.repay(200 ether);
        vm.stopPrank();

        (, uint256 borrowed, uint256 hf) = pool.getUserPosition(alice);
        assertEq(paid, 100 ether);
        assertEq(borrowed, 0);
        assertEq(hf, type(uint256).max);
    }

    function testWithdrawWithDebtWhenStillHealthy() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(50 ether);
        pool.withdraw(20 ether);
        vm.stopPrank();

        (uint256 deposited, uint256 borrowed, uint256 hf) = pool.getUserPosition(alice);
        assertEq(deposited, 80 ether);
        assertEq(borrowed, 50 ether);
        assertGt(hf, 1e18);
    }

    function testWithdrawRevertsWhenHealthFactorWouldFallBelowOne() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(100 ether);
        vm.expectRevert(LendingPool.HealthFactorTooLow.selector);
        pool.withdraw(50 ether);
        vm.stopPrank();
    }

    function testBorrowWithZeroCollateralReverts() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.ExceedsMaxLtv.selector);
        pool.borrow(1 ether);
    }

    function testInterestAccruesOverTime() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(100 ether);
        vm.warp(block.timestamp + 100);
        vm.stopPrank();

        assertEq(pool.debtOf(alice), 110 ether);
    }

    function testLiquidationAfterPriceDrop() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(100 ether);
        vm.stopPrank();

        oracle.setPrice(1e18);

        uint256 liquidatorCollateralBefore = collateralToken.balanceOf(liquidator);

        vm.prank(liquidator);
        (uint256 repaid, uint256 seized) = pool.liquidate(alice, 40 ether);

        (uint256 deposited, uint256 borrowed, uint256 hf) = pool.getUserPosition(alice);
        assertEq(repaid, 40 ether);
        assertEq(seized, 42 ether);
        assertEq(deposited, 58 ether);
        assertEq(borrowed, 60 ether);
        assertLt(hf, 1e18);
        assertEq(collateralToken.balanceOf(liquidator), liquidatorCollateralBefore + 42 ether);
    }

    function testHealthyPositionCannotBeLiquidated() public {
        vm.startPrank(alice);
        pool.deposit(100 ether);
        pool.borrow(50 ether);
        vm.stopPrank();

        vm.prank(liquidator);
        vm.expectRevert(LendingPool.PositionHealthy.selector);
        pool.liquidate(alice, 10 ether);
    }
}
