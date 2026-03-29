// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {AMM} from "../src/AMM.sol";
import {LendingPool} from "../src/LendingPool.sol";

contract DeployAllScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        MockERC20 tokenA = new MockERC20("Token A", "TKA", 18);
        MockERC20 tokenB = new MockERC20("Token B", "TKB", 18);
        MockERC20 debtToken = new MockERC20("Debt Token", "DBT", 18);
        MockPriceOracle oracle = new MockPriceOracle(2e18);
        AMM amm = new AMM(address(tokenA), address(tokenB), "AMM LP Token", "ALP");
        LendingPool lendingPool = new LendingPool(address(tokenA), address(debtToken), address(oracle), 1e15);

        tokenA.mint(msg.sender, 1_000_000 ether);
        tokenB.mint(msg.sender, 1_000_000 ether);
        debtToken.mint(address(lendingPool), 1_000_000 ether);

        amm;
        lendingPool;

        vm.stopBroadcast();
    }
}
