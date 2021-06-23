// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Whitelist.sol";


interface IParams {
    function isLiquidation(uint256 price) external view returns (bool);
    function cost() external view returns (uint256);
    function setStakeRate(uint256 _stakerRate) external;
}

interface IEsm {
    function shutdown() external;

    function isClosed() external view returns (bool);
}

contract Oracle is Whitelist {
    using SafeMath for uint256;

    /// @dev Token-usdt price
    uint256 public val;
    /// @dev Price update date(s)
    uint256 public time;
    /// @dev Oracle Name
    string public name;

    /// @dev Oracle update success event
    event OracleUpdate(uint256 val, uint256 time);

    /// @dev Dparam address
    IParams params;

    /// @dev Esm address
    IEsm esm;

    /**
     * @dev Construct a new Oracle
     * @param _params Dynamic parameter contract address
     * @param _esm Esm parameter contract address
     */
    constructor(address _esm, address _params, string memory _name) public {
        esm = IEsm(_esm);
        params = IParams(_params);
        name = _name;
    }

    /**
     * @dev Chain-off push price to chain-on
     *  price = token/usd * coin_decimals
     *  stakeRate = cost * coin_decimals / price
     * @param price token-usd price decimals
     */
    function poke(uint256 price) public onlyWhitelisted {
        require(!esm.isClosed(), "System closed yet.");

        val = price;
        time = block.timestamp;
        if (params.isLiquidation(val)) {
            esm.shutdown();
        } else {
            emit OracleUpdate(val, time);
        }

        emit OracleUpdate(val, time);
    }

    /**
     * @dev Anybody can read the oracle price 查询当前的喂价值
     */
    function peek() public view returns (uint256) {
        return val;
    }
}