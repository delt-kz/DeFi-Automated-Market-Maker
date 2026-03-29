// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SimpleERC20} from "../../src/SimpleERC20.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract SimpleERC20Test is Test {
    MockERC20 internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        token = new MockERC20("Test Token", "TST", 18);
        token.mint(alice, 1_000 ether);
        token.mint(bob, 500 ether);
    }

    function testMintIncreasesBalanceAndSupply() public {
        token.mint(carol, 250 ether);

        assertEq(token.balanceOf(carol), 250 ether);
        assertEq(token.totalSupply(), 1_750 ether);
    }

    function testMintToZeroAddressReverts() public {
        vm.expectRevert(SimpleERC20.ZeroAddress.selector);
        token.mint(address(0), 1 ether);
    }

    function testTransferMovesBalance() public {
        vm.prank(alice);
        bool success = token.transfer(bob, 200 ether);

        assertTrue(success);
        assertEq(token.balanceOf(alice), 800 ether);
        assertEq(token.balanceOf(bob), 700 ether);
    }

    function testTransferEntireBalance() public {
        vm.prank(bob);
        bool success = token.transfer(carol, 500 ether);

        assertTrue(success);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 500 ether);
    }

    function testTransferToZeroAddressReverts() public {
        vm.prank(alice);
        vm.expectRevert(SimpleERC20.ZeroAddress.selector);
        token.transfer(address(0), 1 ether);
    }

    function testTransferZeroAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert(SimpleERC20.ZeroAmount.selector);
        token.transfer(bob, 0);
    }

    function testTransferInsufficientBalanceReverts() public {
        vm.prank(bob);
        vm.expectRevert(SimpleERC20.InsufficientBalance.selector);
        token.transfer(alice, 501 ether);
    }

    function testApproveSetsAllowance() public {
        vm.prank(alice);
        token.approve(bob, 300 ether);

        assertEq(token.allowance(alice, bob), 300 ether);
    }

    function testApproveZeroSpenderReverts() public {
        vm.prank(alice);
        vm.expectRevert(SimpleERC20.ZeroAddress.selector);
        token.approve(address(0), 1 ether);
    }

    function testTransferFromUsesAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 300 ether);
        vm.stopPrank();

        vm.prank(bob);
        bool success = token.transferFrom(alice, carol, 120 ether);

        assertTrue(success);
        assertEq(token.balanceOf(alice), 880 ether);
        assertEq(token.balanceOf(carol), 120 ether);
        assertEq(token.allowance(alice, bob), 180 ether);
    }

    function testTransferFromWithMaxAllowanceDoesNotDecreaseAllowance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        bool success = token.transferFrom(alice, carol, 50 ether);

        assertTrue(success);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function testTransferFromInsufficientAllowanceReverts() public {
        vm.prank(alice);
        token.approve(bob, 10 ether);

        vm.prank(bob);
        vm.expectRevert(SimpleERC20.InsufficientAllowance.selector);
        token.transferFrom(alice, carol, 11 ether);
    }

    function testTransferFromInsufficientBalanceReverts() public {
        vm.prank(carol);
        token.approve(bob, 10 ether);

        vm.prank(bob);
        vm.expectRevert(SimpleERC20.InsufficientBalance.selector);
        token.transferFrom(carol, alice, 1 ether);
    }

    function testFuzzTransfer(address receiver, uint256 amount) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != alice);

        uint256 boundedAmount = bound(amount, 1, token.balanceOf(alice));
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 receiverBalanceBefore = token.balanceOf(receiver);

        vm.prank(alice);
        bool success = token.transfer(receiver, boundedAmount);

        assertTrue(success);
        assertEq(token.balanceOf(alice), aliceBalanceBefore - boundedAmount);
        assertEq(token.balanceOf(receiver), receiverBalanceBefore + boundedAmount);
        assertEq(token.totalSupply(), 1_500 ether);
    }
}
