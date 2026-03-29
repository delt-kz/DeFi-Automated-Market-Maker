// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";

contract ERC20Handler is Test {
    MockERC20 public immutable token;
    uint256 public immutable initialSupply;

    address[] internal actors;

    constructor(MockERC20 token_) {
        token = token_;
        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));
        actors.push(makeAddr("actor4"));

        initialSupply = 1_000_000 ether;
        uint256 share = initialSupply / actors.length;

        for (uint256 i = 0; i < actors.length; i++) {
            token.mint(actors[i], share);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];

        if (from == to) {
            return;
        }

        uint256 balance = token.balanceOf(from);
        if (balance == 0) {
            return;
        }

        uint256 boundedAmount = bound(amount, 1, balance);

        vm.prank(from);
        bool success = token.transfer(to, boundedAmount);
        assertTrue(success);
    }

    function approveAndTransferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 receiverSeed,
        uint256 approvalAmount,
        uint256 spendAmount
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address receiver = actors[receiverSeed % actors.length];

        if (owner == spender) {
            return;
        }

        uint256 balance = token.balanceOf(owner);
        if (balance == 0) {
            return;
        }

        uint256 boundedApproval = bound(approvalAmount, 0, balance);

        vm.prank(owner);
        token.approve(spender, boundedApproval);

        if (boundedApproval == 0) {
            return;
        }

        uint256 boundedSpend = bound(spendAmount, 1, boundedApproval);

        vm.prank(spender);
        bool success = token.transferFrom(owner, receiver, boundedSpend);
        assertTrue(success);
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 index) external view returns (address) {
        return actors[index];
    }
}
