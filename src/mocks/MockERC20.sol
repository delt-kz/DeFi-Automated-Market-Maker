// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SimpleERC20} from "../SimpleERC20.sol";

contract MockERC20 is SimpleERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) SimpleERC20(name_, symbol_, decimals_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
