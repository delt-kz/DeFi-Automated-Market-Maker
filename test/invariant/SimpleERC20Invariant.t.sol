// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {ERC20Handler} from "./handlers/ERC20Handler.sol";

contract SimpleERC20InvariantTest is StdInvariant, Test {
    MockERC20 internal token;
    ERC20Handler internal handler;

    function setUp() public {
        token = new MockERC20("Invariant Token", "IVT", 18);
        handler = new ERC20Handler(token);
        targetContract(address(handler));
    }

    function invariantTotalSupplyNeverChangesAfterTransfers() public view {
        assertEq(token.totalSupply(), handler.initialSupply());
    }

    function invariantNoBalanceExceedsTotalSupply() public view {
        uint256 totalSupply = token.totalSupply();
        uint256 actorsLength = handler.actorCount();

        for (uint256 i = 0; i < actorsLength; i++) {
            assertLe(token.balanceOf(handler.actorAt(i)), totalSupply);
        }
    }

    function invariantSumOfTrackedBalancesMatchesTotalSupply() public view {
        uint256 actorsLength = handler.actorCount();
        uint256 sum;

        for (uint256 i = 0; i < actorsLength; i++) {
            sum += token.balanceOf(handler.actorAt(i));
        }

        assertEq(sum, token.totalSupply());
    }
}
