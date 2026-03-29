// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

interface IPriceOracle {
    function getPrice() external view returns (uint256);
}

contract LendingPool {
    error ZeroAmount();
    error ExceedsMaxLtv();
    error InsufficientCollateral();
    error InsufficientPoolLiquidity();
    error NoDebt();
    error HealthFactorTooLow();
    error PositionHealthy();

    uint256 public constant MAX_LTV = 75;
    uint256 public constant LIQUIDATION_THRESHOLD = 75;
    uint256 public constant LIQUIDATION_BONUS = 5;
    uint256 public constant PRECISION = 1e18;

    IERC20 public immutable collateralToken;
    IERC20 public immutable debtToken;
    IPriceOracle public immutable oracle;
    uint256 public immutable borrowRatePerSecond;

    struct Position {
        uint256 collateral;
        uint256 debt;
        uint256 lastAccrued;
    }

    mapping(address => Position) public positions;

    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed user, uint256 repaid, uint256 collateralSeized);

    constructor(address collateralToken_, address debtToken_, address oracle_, uint256 borrowRatePerSecond_) {
        collateralToken = IERC20(collateralToken_);
        debtToken = IERC20(debtToken_);
        oracle = IPriceOracle(oracle_);
        borrowRatePerSecond = borrowRatePerSecond_;
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _accrue(msg.sender);
        positions[msg.sender].collateral += amount;

        if (!collateralToken.transferFrom(msg.sender, address(this), amount)) revert InsufficientCollateral();
        emit Deposit(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _accrue(msg.sender);

        Position storage position = positions[msg.sender];
        uint256 newDebt = position.debt + amount;

        if (newDebt > _maxBorrowable(position.collateral)) revert ExceedsMaxLtv();
        if (debtToken.balanceOf(address(this)) < amount) revert InsufficientPoolLiquidity();

        position.debt = newDebt;
        position.lastAccrued = block.timestamp;

        if (!debtToken.transfer(msg.sender, amount)) revert InsufficientPoolLiquidity();
        emit Borrow(msg.sender, amount);
    }

    function repay(uint256 amount) external returns (uint256 paid) {
        if (amount == 0) revert ZeroAmount();

        _accrue(msg.sender);

        Position storage position = positions[msg.sender];
        uint256 currentDebt = position.debt;
        if (currentDebt == 0) revert NoDebt();

        paid = amount > currentDebt ? currentDebt : amount;
        position.debt = currentDebt - paid;
        position.lastAccrued = block.timestamp;

        if (!debtToken.transferFrom(msg.sender, address(this), paid)) revert NoDebt();
        emit Repay(msg.sender, paid);
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _accrue(msg.sender);

        Position storage position = positions[msg.sender];
        if (position.collateral < amount) revert InsufficientCollateral();

        uint256 remainingCollateral = position.collateral - amount;
        if (position.debt != 0 && _healthFactor(remainingCollateral, position.debt) <= PRECISION) {
            revert HealthFactorTooLow();
        }

        position.collateral = remainingCollateral;
        if (!collateralToken.transfer(msg.sender, amount)) revert InsufficientCollateral();

        emit Withdraw(msg.sender, amount);
    }

    function liquidate(address user, uint256 repayAmount) external returns (uint256 repaid, uint256 collateralSeized) {
        if (repayAmount == 0) revert ZeroAmount();

        _accrue(user);

        Position storage position = positions[user];
        if (position.debt == 0) revert NoDebt();
        if (_healthFactor(position.collateral, position.debt) >= PRECISION) revert PositionHealthy();

        uint256 price = oracle.getPrice();
        uint256 maxRepayFromCollateral = (position.collateral * price * 100) / (PRECISION * (100 + LIQUIDATION_BONUS));

        repaid = repayAmount > position.debt ? position.debt : repayAmount;
        if (repaid > maxRepayFromCollateral) {
            repaid = maxRepayFromCollateral;
        }
        if (repaid == 0) revert ZeroAmount();

        collateralSeized = (repaid * PRECISION * (100 + LIQUIDATION_BONUS)) / (price * 100);

        position.debt -= repaid;
        position.collateral -= collateralSeized;
        position.lastAccrued = block.timestamp;

        if (!debtToken.transferFrom(msg.sender, address(this), repaid)) revert NoDebt();
        if (!collateralToken.transfer(msg.sender, collateralSeized)) revert InsufficientCollateral();

        emit Liquidate(msg.sender, user, repaid, collateralSeized);
    }

    function debtOf(address user) public view returns (uint256) {
        Position memory position = positions[user];

        if (position.debt == 0 || position.lastAccrued == 0) {
            return position.debt;
        }

        uint256 elapsed = block.timestamp - position.lastAccrued;
        uint256 interest = (position.debt * borrowRatePerSecond * elapsed) / PRECISION;

        return position.debt + interest;
    }

    function healthFactor(address user) public view returns (uint256) {
        Position memory position = positions[user];
        return _healthFactor(position.collateral, debtOf(user));
    }

    function maxBorrowable(address user) external view returns (uint256) {
        return _maxBorrowable(positions[user].collateral);
    }

    function getUserPosition(address user) external view returns (uint256 deposited, uint256 borrowed, uint256 hf) {
        Position memory position = positions[user];
        deposited = position.collateral;
        borrowed = debtOf(user);
        hf = _healthFactor(position.collateral, borrowed);
    }

    function _accrue(address user) internal {
        Position storage position = positions[user];

        if (position.lastAccrued == 0) {
            position.lastAccrued = block.timestamp;
            return;
        }

        if (position.debt != 0) {
            position.debt = debtOf(user);
        }

        position.lastAccrued = block.timestamp;
    }

    function _maxBorrowable(uint256 collateralAmount) internal view returns (uint256) {
        uint256 collateralValue = (collateralAmount * oracle.getPrice()) / PRECISION;
        return (collateralValue * MAX_LTV) / 100;
    }

    function _healthFactor(uint256 collateralAmount, uint256 debtAmount) internal view returns (uint256) {
        if (debtAmount == 0) {
            return type(uint256).max;
        }

        uint256 collateralValue = (collateralAmount * oracle.getPrice()) / PRECISION;
        uint256 adjustedCollateral = (collateralValue * LIQUIDATION_THRESHOLD) / 100;
        return (adjustedCollateral * PRECISION) / debtAmount;
    }
}
