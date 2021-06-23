// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDparam.sol";
import "./Whitelist.sol";

interface IOracle {
    function val() external returns (uint256);

    function poke(uint256 price) external;

    function peek() external;
}

interface IESM {
    function isStakePaused() external view returns (bool);

    function isRedeemPaused() external view returns (bool);

    function isClosed() external view returns (bool);

    function time() external view returns (uint256);
}

interface ICoin {
    function burn(address account, uint256 amount) external;

    function mint(address account, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}

contract Stake is Whitelist {
    using SafeMath for uint256;


    /// @dev The amount by staker with token
    mapping(address => uint256) public tokens;
    ///  The amount by staker with coin
    mapping(address => uint256) public coins;
    /// @dev The total amount of out-coin in sys
    uint256 public totalCoin;
    /// @dev The total amount of stake-token in sys
    uint256 public totalToken;

    /// @dev Cumulative  service fee.
    uint256 public sFee;

    /// @dev Dparam address
    IDparam params;
    /// @dev Oracle address
    IOracle orcl;
    /// @dev Esm address
    IESM esm;
    /// @dev Coin address
    ICoin coin;
    /// @dev Token address
    IERC20 token;

    /// @dev Setup Oracle address success
    event SetupOracle(address orcl);
    /// @dev Setup Dparam address success
    event SetupParam(address param);
    /// @dev Setup Esm address success
    event SetupEsm(address esm);
    /// @dev Setup Token&Coin address success
    event SetupCoin(address token, address coin);
    /// @dev Stake success
    event StakeEvent(uint256 token, uint256 coin);
    /// @dev redeem success
    event RedeemEvent(uint256 token, uint256 move, uint256 fee, uint256 coin);

    /**
     * @dev Construct a new Stake, owner by msg.sender
     */
    constructor(
        address _esm,
        address _param,
        address _orcl
    ) public {
        params = IDparam(_param);
        orcl = IOracle(_orcl);
        esm = IESM(_esm);
    }

    modifier notClosed() {
        require(!esm.isClosed(), "System closed");
        _;
    }

    /**
     * @dev reset Dparams address.
     * @param _params Configuration dynamic params contract address
     */
    function setupParams(address _params) public onlyWhitelisted {
        params = IDparam(_params);
        emit SetupParam(_params);
    }

    /**
     * @dev reset Oracle address.
     * @param _orcl Configuration Oracle contract address
     */
    function setupOracle(address _orcl) public onlyWhitelisted {
        orcl = IOracle(_orcl);
        emit SetupOracle(_orcl);
    }

    /**
     * @dev reset Esm address.
     * @param _esm Configuration Esm contract address
     */
    function setupEsm(address _esm) public onlyWhitelisted {
        esm = IESM(_esm);
        emit SetupEsm(_esm);
    }

    /**
     * @dev get Dparam address.
     * @return Dparam contract address
     */
    function getParamsAddr() public view returns (address) {
        return address(params);
    }

    /**
     * @dev get Oracle address.
     * @return Oracle contract address
     */
    function getOracleAddr() public view returns (address) {
        return address(orcl);
    }

    /**
     * @dev get Esm address.
     * @return Esm contract address
     */
    function getEsmAddr() public view returns (address) {
        return address(esm);
    }

    /**
     * @dev get token of staking address.
     * @return ERC20 address
     */
    function getCoinAddress() public view returns (address) {
        return address(coin);
    }

    /**
     * @dev get StableToken address.
     * @return ERC20 address
     */
    function getTokenAddress() public view returns (address) {
        return address(token);
    }

    /**
     * @dev inject token address & coin address only once.
     * @param _token token address
     * @param _coin coin address
     */
    function setup(address _token, address _coin) public onlyWhitelisted {
        require(
            address(token) == address(0) && address(coin) == address(0),
            "setuped yet."
        );
        token = IERC20(_token);
        coin = ICoin(_coin);

        emit SetupCoin(_token, _coin);
    }

    /**
     * @dev Get the number of debt by the `account`
     * @param account token address
     * @return (tokenAmount,coinAmount)
     */
    function debtOf(address account) public view returns (uint256, uint256) {
        return (tokens[account], coins[account]);
    }

    /**
     * @dev Determine whether the current pledge rate reaches the pledge rate
     * @param staker token address
     * tokens[staker] * price > cost * ONE_COIN * coins[staker]
     */
    function _judgePledgeRate(address staker) internal returns (bool) {
        if (coins[staker] > 0) {
            return
                tokens[staker].mul(orcl.val()).div(coins[staker]) >=
                params.cost().mul(params.one_coin());
        }
    }


    /**
     * @dev Get the number of debt by the `account`
     * @param coinAmount The amount that staker want to get stableToken
     * coinAmount / ONE_COIN = tokenAmount / ONE_TOKEN / stakeRate
     */
    function getInputToken(uint256 coinAmount)
        public
        view
        returns (uint256 tokenAmount)
    {
        tokenAmount = coinAmount.div(params.one_coin()).mul(params.stakeRate()) * params.one_token();
    }

    /**
     * @dev Normally redeem anyAmount internal
     * @param coinAmount The number of coin will be staking
     */
    function stake(uint256 coinAmount) external notClosed {
        require(!esm.isStakePaused(), "Stake paused");
        require(coinAmount > 0, "The quantity is less than the minimum");
        require(orcl.val() > 0, "Oracle price not initialized.");

        require(
            params.isUpperLimit(totalCoin),
            "The total amount of pledge in the current system has reached the upper limit."
        );

        address from = msg.sender;

        if (coins[from] == 0) {
            require(
                coinAmount >= params.minMint(),
                "First make coin must grater than 100."
            );
        }

        uint256 tokenAmount = getInputToken(coinAmount);

        if (!_judgePledgeRate(from) && coins[from] > 0) {
            coinAmount = coinAmount.sub(
                coins[from].sub(
                    orcl.val().mul(tokens[from]).div(params.cost()).div(params.one_coin())
                )
            );
        }

        token.transferFrom(from, address(this), tokenAmount);

        coin.mint(from, coinAmount);

        totalCoin = totalCoin.add(coinAmount);
        totalToken = totalToken.add(tokenAmount);
        coins[from] = coins[from].add(coinAmount);
        tokens[from] = tokens[from].add(tokenAmount);

        emit StakeEvent(tokenAmount, coinAmount);
    }

    /**
     * @dev Normally redeem anyAmount internal
     * @param coinAmount The number of coin will be redeemed
     * @param receiver Address of receiving
     */
    function _normalRedeem(uint256 coinAmount, address receiver)
        internal
        notClosed
    {
        require(!esm.isRedeemPaused(), "Redeem paused");
        address staker = msg.sender;
        require(coins[staker] > 0, "No collateral");
        require(coinAmount > 0, "The quantity is less than zero");
        require(coinAmount <= coins[staker], "input amount overflow");

        uint256 coinVal;
        uint256 tokenAmount;
        if (!_judgePledgeRate(receiver)) {
            coinVal = orcl.val().mul(tokens[receiver]).div(params.cost()).div(params.one_coin());
            tokenAmount = coinVal.mul(tokens[receiver]).div(coins[receiver]);
        } else {
            tokenAmount = coinAmount.mul(tokens[receiver]).div(coins[receiver]);
        }

        uint256 feeRate = params.feeRate();
        uint256 fee = tokenAmount.mul(feeRate).div(1000);
        uint256 move = tokenAmount.sub(fee);
        sFee = sFee.add(fee);
        token.transfer(params.feeAddress(), fee);
        coin.burn(staker, coinAmount);
        token.transfer(receiver, move);

        if (tokenAmount >= tokens[staker]) {
            tokens[staker] = 0;
        } else {
            tokens[staker] = tokens[staker].sub(tokenAmount);
        }
        coins[staker] = coins[staker].sub(coinAmount);
        totalCoin = totalCoin.sub(coinAmount);
        totalToken = totalToken.sub(tokenAmount);

        emit RedeemEvent(tokenAmount, move, fee, coinAmount);
    }

    /**
     * @dev Abnormally redeem anyAmount internal
     * @param coinAmount The number of coin will be redeemed
     * @param receiver Address of receiving
     */
    function _abnormalRedeem(uint256 coinAmount, address receiver) internal {
        require(esm.isClosed(), "System not Closed yet.");
        address from = msg.sender;
        require(coinAmount > 0, "The quantity is less than zero");
        require(coin.balanceOf(from) > 0, "The coin no balance.");
        require(coinAmount <= coin.balanceOf(from), "Coin balance exceed");

        uint256 tokenAmount = coinAmount.mul(totalToken).div(totalCoin);

        coin.burn(from, coinAmount);
        token.transfer(receiver, tokenAmount);

        if (tokens[from] >= tokenAmount) {
            tokens[from] = tokens[from].sub(tokenAmount);
        } else {
            tokens[from] = 0;
        }

        if (coins[from] >= coinAmount) {
            coins[from] = coins[from].sub(coinAmount);
        } else {
            coins[from] = 0;
        }

        totalCoin = totalCoin.sub(coinAmount);
        totalToken = totalToken.sub(tokenAmount);

        emit RedeemEvent(tokenAmount, tokenAmount, 0, coinAmount);
    }

    /**
     * @dev Normally redeem anyAmount
     * @param coinAmount The number of coin will be redeemed
     * @param receiver Address of receiving
     */
    function redeem_(uint256 coinAmount, address receiver) public {
        _normalRedeem(coinAmount, receiver);
    }

    /**
     * @dev Normally redeem anyAmount to msg.sender
     * @param coinAmount The number of coin will be redeemed
     */
    function redeem(uint256 coinAmount) public {
        redeem_(coinAmount, msg.sender);
    }

    /**
     * @dev normally redeem them all at once
     * @param holder reciver
     */
    function redeemMax(address holder) public {
        redeem_(coins[msg.sender], holder);
    }

    /**
     * @dev normally redeem them all at once to msg.sender
     */
    function redeemMax() public {
        redeemMax(msg.sender);
    }

    /**
     * @dev System shutdown under the redemption rule
     * @param coinAmount The number coin
     * @param receiver Address of receiving
     */
    function oRedeem(uint256 coinAmount, address receiver) public {
        _abnormalRedeem(coinAmount, receiver);
    }

    /**
     * @dev System shutdown under the redemption rule
     * @param coinAmount The number coin
     */
    function oRedeem(uint256 coinAmount) public {
        oRedeem(coinAmount, msg.sender);
    }
}