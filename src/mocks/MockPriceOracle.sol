// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockPriceOracle {
    uint256 public price;

    constructor(uint256 price_) {
        price = price_;
    }

    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }
}
