// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";
import {LPToken} from "./LPToken.sol";
import {ReentrancyGuardLite} from "./utils/ReentrancyGuardLite.sol";

contract AMM is ReentrancyGuardLite {
    error InvalidToken();
    error IdenticalTokens();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientOutputAmount();

    IERC20 public immutable token0;
    IERC20 public immutable token1;
    LPToken public immutable lpToken;

    uint256 public reserve0;
    uint256 public reserve1;

    event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
    event Swap(
        address indexed trader, address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut
    );

    constructor(address token0_, address token1_, string memory lpName_, string memory lpSymbol_) {
        if (token0_ == address(0) || token1_ == address(0)) revert ZeroAddress();
        if (token0_ == token1_) revert IdenticalTokens();

        token0 = IERC20(token0_);
        token1 = IERC20(token1_);
        lpToken = new LPToken(lpName_, lpSymbol_, address(this));
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired, uint256 minLiquidity)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        if (amount0Desired < 1 || amount1Desired < 1) revert ZeroAmount();

        uint256 totalLiquidity = lpToken.totalSupply();

        if (totalLiquidity == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            liquidity = _sqrt(amount0 * amount1);
        } else {
            uint256 amount1Optimal = (amount0Desired * reserve1) / reserve0;

            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
                liquidity = (amount0Desired * totalLiquidity) / reserve0;
            } else {
                uint256 amount0Optimal = (amount1Desired * reserve0) / reserve1;
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
                liquidity = (amount1Desired * totalLiquidity) / reserve1;
            }
        }

        if (liquidity < 1 || liquidity < minLiquidity) revert InsufficientLiquidityMinted();

        _safeTransferFrom(token0, msg.sender, address(this), amount0);
        _safeTransferFrom(token1, msg.sender, address(this), amount1);
        lpToken.mint(msg.sender, liquidity);
        _updateReserves();

        emit LiquidityAdded(msg.sender, amount0, amount1, liquidity);
    }

    function removeLiquidity(uint256 liquidity, uint256 minAmount0, uint256 minAmount1)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity < 1) revert ZeroAmount();

        uint256 totalLiquidity = lpToken.totalSupply();
        amount0 = (liquidity * reserve0) / totalLiquidity;
        amount1 = (liquidity * reserve1) / totalLiquidity;

        if (amount0 < 1 || amount1 < 1 || amount0 < minAmount0 || amount1 < minAmount1) {
            revert InsufficientLiquidityBurned();
        }

        lpToken.burn(msg.sender, liquidity);
        _safeTransfer(token0, msg.sender, amount0);
        _safeTransfer(token1, msg.sender, amount1);
        _updateReserves();

        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity);
    }

    function swap(address tokenIn, uint256 amountIn, uint256 minAmountOut, address to)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn < 1) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();

        bool zeroForOne = false;
        IERC20 inputToken = token0;
        IERC20 outputToken = token1;
        uint256 reserveIn = 0;
        uint256 reserveOut = 0;

        if (tokenIn == address(token0)) {
            zeroForOne = true;
            inputToken = token0;
            outputToken = token1;
            reserveIn = reserve0;
            reserveOut = reserve1;
        } else if (tokenIn == address(token1)) {
            inputToken = token1;
            outputToken = token0;
            reserveIn = reserve1;
            reserveOut = reserve0;
        } else {
            revert InvalidToken();
        }

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < minAmountOut) revert InsufficientOutputAmount();

        _safeTransferFrom(inputToken, msg.sender, address(this), amountIn);
        _safeTransfer(outputToken, to, amountOut);
        _updateReserves();

        emit Swap(msg.sender, tokenIn, amountIn, zeroForOne ? address(token1) : address(token0), amountOut);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        if (amountIn < 1 || reserveIn < 1 || reserveOut < 1) revert ZeroAmount();

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    function _updateReserves() internal {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));
    }

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        if (!token.transferFrom(from, to, amount)) revert InvalidToken();
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        if (!token.transfer(to, amount)) revert InvalidToken();
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y == 0) {
            return 0;
        }

        if (y <= 3) {
            return 1;
        }

        z = y;
        uint256 x = (y / 2) + 1;

        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }
}
