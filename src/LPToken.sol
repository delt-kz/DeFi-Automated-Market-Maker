// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SimpleERC20} from "./SimpleERC20.sol";

contract LPToken is SimpleERC20 {
    error NotAMM();

    address public immutable amm;

    constructor(string memory name_, string memory symbol_, address amm_) SimpleERC20(name_, symbol_, 18) {
        amm = amm_;
    }

    modifier onlyAMM() {
        if (msg.sender != amm) revert NotAMM();
        _;
    }

    function mint(address to, uint256 amount) external onlyAMM {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyAMM {
        _burn(from, amount);
    }
}
