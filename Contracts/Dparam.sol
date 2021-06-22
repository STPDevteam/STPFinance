// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IDparam.sol";
import "./Whitelist.sol";
import "hardhat/console.sol";

contract Dparam is Whitelist, IDparam {
    using SafeMath for uint256;

    /// @dev Initial ratio 35 token mint -> 1 coin
    uint256 public override stakeRate = 35;
    /// @dev The collateral rate of liquidation
    uint256 public override liquidationLine = 110;
    /// @dev Redemption rate 0.3%
    uint256 public override feeRate = 3;

    /// @dev Minimum number of COINS for the first time
    uint256 public override one_coin = 1e6;
    uint256 public override one_token = 1e18;
    uint256 public override minMint = 100 * one_coin;
    ///@dev UpperLimit for COINS for the System.
    uint256 public override coinUpperLimit = 10000 * one_coin;
    ///@dev LowLimit for COINS for the System.
    uint256 public override coinLowLimit = 100 * one_coin;
    ///@dev Set the cost of the Stake
    uint256 public override cost = 7;

    event StakeRateEvent(uint256 stakeRate);
    /// @dev Reset fee event
    event FeeRateEvent(uint256 feeRate);
    /// @dev Reset liquidationLine event
    event LiquidationLineEvent(uint256 liquidationRate);
    /// @dev Reset minMint event
    event MinMintEvent(uint256 minMint);
    event CostEvent(uint256 cost, uint256 price);
    event CoinUpperLimitEvent(uint256 coinUpperLimit);
    event CoinLowLimitEvent(uint256 coinLowLimit);

    /**
     * @dev Construct a new Dparam, owner by msg.sender
     */
    constructor(uint256 _coin, uint256 _token) public {
        one_coin = _coin;
        one_token = _token;
    }

    /**
     * @dev Reset feeRate
     * @param _feeRate New number of feeRate
     */
    function setFeeRate(uint256 _feeRate) override external onlyWhitelisted {
        feeRate = _feeRate;
        emit FeeRateEvent(feeRate);
    }

    /**
     * @dev Reset liquidationLine
     * @param _liquidationLine New number of liquidationLine
     */
    function setLiquidationLine(uint256 _liquidationLine) override external onlyWhitelisted {
        liquidationLine = _liquidationLine;
        emit LiquidationLineEvent(liquidationLine);
    }

    /**
     * @dev Reset minMint
     * @param _minMint New number of minMint
     */
    function setMinMint(uint256 _minMint) override external onlyWhitelisted {
        minMint = _minMint;
        emit MinMintEvent(minMint);
    }

    /**
     * @dev Reset stakeRate for DynamicPledge
     * @param price = (token/usdt) * decimals
     */
    function setStakeRate(uint256 price) override external onlyWhitelisted {
        console.log(cost, one_coin, price);
        stakeRate = cost.mul(one_coin).div(price);
        console.log('setStakeRate', stakeRate);
        emit StakeRateEvent(stakeRate);
    }

    /**
     * @dev Reset coinUpperLimit
     * @param _coinUpperLimit New number of coinUpperLimit
     */
    function setCoinUpperLimit(uint256 _coinUpperLimit) override external onlyWhitelisted {
        coinUpperLimit = _coinUpperLimit;
        emit CoinUpperLimitEvent(coinUpperLimit);
    }

    /**
     * @dev Reset coinLowLimit
     * @param _coinLowLimit New number of coinLowLimit
     */
    function setCoinLowLimit(uint256 _coinLowLimit) override external onlyWhitelisted {
        coinLowLimit = _coinLowLimit;
        emit CoinLowLimitEvent(coinLowLimit);
    }

    /**
     * @dev Reset cost
     * @param _cost New number of _cost
     * @param price New number of price
     */
    function setCost(uint256 _cost, uint256 price) override external onlyWhitelisted {
        cost = _cost;
        stakeRate = cost.mul(one_coin).div(price);
        emit CostEvent(cost, price);
    }

    /**
     * @dev Check Is it below the clearing line
     * @param price The token/usdt price
     * @return Whether the clearing line has been no exceeded
     */
    function isLiquidation(uint256 price) override external view returns (bool) {
        return price.mul(stakeRate).mul(100) <= liquidationLine.mul(one_coin);
    }

    /**
     * @dev Determine if the exchange value at the current rate is less than cost
     * @param price The token/usdt price
     * @return The value of Checking
     */
    function isNormal(uint256 price) override external view returns (bool) {
        return price.mul(stakeRate) >= one_coin.mul(cost);
    }

    /**
     * @dev Verify that the amount of Staking in the current system has reached the upper limit
     * @param totalCoin The number of the Staking COINS
     * @return The value of Checking
     */
    function isUpperLimit(uint256 totalCoin) override external view returns (bool) {
        console.log('isUpperLimit', totalCoin, coinUpperLimit);
        return totalCoin <= coinUpperLimit;
    }

    /**
     * @dev Verify that the amount of Staking in the current system has reached the lowest limit
     * @param totalCoin The number of the Staking COINS
     * @return The value of Checking
     */
    function isLowestLimit(uint256 totalCoin) override external view returns (bool) {
        return totalCoin >= coinLowLimit;
    }
}
