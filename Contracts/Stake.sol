// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDparam.sol";
import "./Whitelist.sol";
import "hardhat/console.sol";

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

    /**
     * @dev reward pools state
     * @param index Accumulated earnings index by staker
     * @param reward Accumulative reward
     */
    struct StakerState {
        uint256 index;
        uint256 reward;
    }

    /**
     * @dev reward array
     * @param coinAddress The address of reward coin
     * @param rewardTotal The total number or reward
     * @param rewardSpeed The speed of reward delivery
     * @param initialIndex Inital index
     * @param blockNumber The block number
     * @param doubleScale Amplification factor
     * @param coin Inject reward coin
     */
    struct RewardCoin {
        address coinAddress;
        uint256 rewardTotal;
        uint256 rewardSpeed;
        uint256 initialIndex;
        uint256 index;
        uint256 blockNumber;
        uint256 doubleScale;
        IERC20 coin;
    }

    RewardCoin[] public rewardCoins;

    /// @dev All staker-instances state
    mapping(address => StakerState[]) public stakerStateArray;
    mapping(address => uint256) public rewardCoinIndex;
    /// @dev The amount by staker with token
    mapping(address => uint256) public tokens;
    ///  The amount by staker with coin
    mapping(address => uint256) public coins;
    ///@dev determines whether the user initializes the currency
    mapping(address => bool) public isOrNot;
    /// @dev The total amount of out-coin in sys
    uint256 public totalCoin;
    /// @dev The total amount of stake-token in sys
    uint256 public totalToken;

    /// @dev Cumulative  service fee.
    uint256 public sFee;
    uint256 public one_coin = 1e6;
    uint256 public one_token = 1e18;
    address constant blackhole = 0x1111111111111111111111111111111111111111;

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
    /// @dev Update index success
    event IndexUpdate(uint256 delt, uint256 block, uint256 index);
    /// @dev ClaimToken success
    event ClaimToken(address holder, uint256 value, address coinAddress);
    /// @dev InjectReward success
    event InjectReward(uint256 amount, address coinAddress);
    /// @dev ExtractReward success
    event ExtractReward(address reciver, uint256 amount, address coinAddress);

    /**
     * @dev Construct a new Stake, owner by msg.sender
  
     */
    constructor(
        address _esm,
        address _param,
        address _orcl
    ) public {
        params = IDparam(_param);
        one_coin = params.one_coin();
        one_token = params.one_token();
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
        one_coin = params.one_coin();
        one_token = params.one_token();
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
                params.cost().mul(one_coin);
        }
    }


    /**
     *@dev Claim the redundant Oin
     *@param staker token address
     */
    function claimOin(address staker) public notClosed {
        require(
            _judgePledgeRate(staker),
            "The current pledge rate does not meet the system pledge rate requirements"
        );

        uint256 redundantOin =
            orcl
                .val()
                .mul(tokens[staker])
                .div(1e8)
                .sub(coins[staker].mul(params.cost()))
                .mul(1e8)
                .div(orcl.val());

        require(
            redundantOin > 0,
            "There are currently no OIN tokens available to collect"
        );
        token.transfer(staker, redundantOin);
        tokens[staker] = tokens[staker].sub(redundantOin);
        totalToken = totalToken.sub(redundantOin);
    }

    /**
     *@dev Claim the redundant USDO
     *@param staker token address
     */
    function claimUSDO(address staker) public notClosed {
        require(
            _judgePledgeRate(staker),
            "The current pledge rate does not meet the system pledge rate requirements"
        );

        uint256 redundantUSDO =
            orcl.val().mul(tokens[staker]).div(params.cost()).div(1e8).sub(
                coins[staker]
            );
        require(
            redundantUSDO > 0,
            "There are currently no USDO tokens available to collect"
        );
        coin.mint(staker, redundantUSDO);
        coins[staker] = coins[staker].add(redundantUSDO);
        totalCoin = totalCoin.add(redundantUSDO);
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
        console.log(coinAmount, one_coin, params.stakeRate(), one_token);
        tokenAmount = coinAmount.div(one_coin).mul(params.stakeRate()) * one_token;
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
                    orcl.val().mul(tokens[from]).div(params.cost()).div(one_coin)
                )
            );
        }

        accuredToken(from);
        token.transferFrom(from, address(this), tokenAmount);

        coin.mint(from, coinAmount);

        totalCoin = totalCoin.add(coinAmount);
        totalToken = totalToken.add(tokenAmount);
        coins[from] = coins[from].add(coinAmount);
        tokens[from] = tokens[from].add(tokenAmount);

        console.log("StakeEvent:", tokenAmount, coinAmount);

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
        accuredToken(staker);
        if (!_judgePledgeRate(receiver)) {
            coinVal = orcl.val().mul(tokens[receiver]).div(params.cost()).div(one_coin);
            tokenAmount = coinVal.mul(tokens[receiver]).div(coins[receiver]);
        } else {
            tokenAmount = coinAmount.mul(tokens[receiver]).div(coins[receiver]);
        }

        uint256 feeRate = params.feeRate();
        uint256 fee = tokenAmount.mul(feeRate).div(1000);
        uint256 move = tokenAmount.sub(fee);
        sFee = sFee.add(fee);
        token.transfer(blackhole, fee);
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
    function redeem(uint256 coinAmount, address receiver) public {
        _normalRedeem(coinAmount, receiver);
    }

    /**
     * @dev Normally redeem anyAmount to msg.sender
     * @param coinAmount The number of coin will be redeemed
     */
    function redeem(uint256 coinAmount) public {
        redeem(coinAmount, msg.sender);
    }

    /**
     * @dev normally redeem them all at once
     * @param holder reciver
     */
    function redeemMax(address holder) public {
        redeem(coins[msg.sender], holder);
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

    /**
     * @dev Refresh reward speed.
     */
    function setRewardSpeed(uint256 speed, address coinAddress)
        public
        onlyWhitelisted
    {
        uint256 rewardCoinSub = rewardCoinIndex[coinAddress];
        updateIndex();
        rewardCoins[rewardCoinSub].rewardSpeed = speed;
    }

    /**
     * @dev Init RewardCoin array
     */
    function InitRewardCoin() public onlyWhitelisted {
        //Fist reward coin information
        addRewardCoin(
            0xD78B0A147EE7879F14a7CEF25761CB58ED978681,
            0,
            2.5e8,
            1e16,
            0,
            1e16
        );
        //Second reward coin information
        addRewardCoin(
            0x836ae4569F4c740A295Fc7a8438C928b7097d446,
            0,
            5e18,
            1e36,
            0,
            1e24
        );
    }

    /**
     * @dev Get rewardCoins
     */
    function getRewardCoins() public view returns (RewardCoin[] memory) {
        return rewardCoins;
    }

    /**
     * @dev Add a new RewardCoin
     */
    function addRewardCoin(
        address coinAddress,
        uint256 rewardTotal,
        uint256 rewardSpeed,
        uint256 initialIndex,
        uint256 index,
        uint256 doubleScale
    ) public onlyWhitelisted {
        require(
            rewardCoins.length <= 20,
            "The currency slot has been used up, please modify other currency information as appropriate"
        );
        for (uint256 i = 0; i < rewardCoins.length; i++) {
            require(
                coinAddress != rewardCoins[i].coinAddress,
                "The current currency has been added, please add a new currency."
            );
        }
        uint256 blockNumber = getBlockNumber();
        rewardCoins.push(
            RewardCoin(
                coinAddress,
                rewardTotal,
                rewardSpeed,
                initialIndex,
                index,
                blockNumber,
                doubleScale,
                IERC20(coinAddress)
            )
        );
        rewardCoinIndex[coinAddress] = rewardCoins.length - 1;
    }

    /**
     * @dev Used to correct the effect of one's actions on one's own earnings
     *         System shutdown will no longer count
     */
    function updateIndex() public {
        if (esm.isClosed()) {
            return;
        }
        uint256 blockNumber = getBlockNumber();
        for (uint256 i = 0; i < rewardCoins.length; i++) {
            uint256 deltBlock = blockNumber.sub(rewardCoins[i].blockNumber);
            if (deltBlock > 0 && params.isLowestLimit(totalCoin)) {
                uint256 accruedReward =
                    rewardCoins[i].rewardSpeed.mul(deltBlock);
                uint256 ratio =
                    totalToken == 0
                        ? 0
                        : accruedReward.mul(rewardCoins[i].doubleScale).div(
                            totalToken
                        );
                rewardCoins[i].index = rewardCoins[i].index.add(ratio);
                rewardCoins[i].blockNumber = blockNumber;
            } else {
                rewardCoins[i].index = rewardCoins[i].index;
                rewardCoins[i].blockNumber = blockNumber;
            }
            emit IndexUpdate(deltBlock, blockNumber, rewardCoins[i].index);
        }
    }

    /**
     * @dev Used to correct the effect of one's actions on one's own earnings
     *         System shutdown will no longer count
     * @param account staker address
     */
    function accuredToken(address account) public returns (uint256) {
        updateIndex();

        if (!isOrNot[account]) {
            // init
            for (uint256 i = 0; i < 20; i++) {
                stakerStateArray[account].push(StakerState(0, 0));
            }
            isOrNot[account] = true;
        }

        // update
        for (uint256 i = 0; i < rewardCoins.length; i++) {
            stakerStateArray[account][i].reward = _getReward(
                account,
                rewardCoins[i].coinAddress
            );
            stakerStateArray[account][i].index = rewardCoins[i].index;
        }
    }

    /**
     * @dev select holder's StateArray
     */
    function getStakerStateArray() public view returns (StakerState[] memory) {
        return stakerStateArray[msg.sender];
    }

    /**
     * @dev Calculate the current holder's mining income
     * @param staker Address of holder
     */
    function _getReward(address staker, address coinAddress)
        internal
        view
        returns (uint256 value)
    {
        uint256 rewardCoinSub = rewardCoinIndex[coinAddress];

        //The reward will not be calculated if the number of Coins in the current system is insufficient
        value = stakerStateArray[staker][rewardCoinSub].reward.add(
            rewardCoins[rewardCoinSub]
                .index
                .sub(stakerStateArray[staker][rewardCoinSub].index)
                .mul(tokens[staker])
                .div(rewardCoins[rewardCoinSub].doubleScale)
        );
    }

    /**
     * @dev Estimate the mortgagor's reward
     * @param account Address of staker
     */
    function getHolderReward(address account, address coinAddress)
        public
        view
        returns (uint256 value)
    {
        uint256 rewardCoinSub = rewardCoinIndex[coinAddress];
        uint256 blockReward2 =
            (totalToken == 0 ||
                esm.isClosed() ||
                !params.isLowestLimit(totalCoin))
                ? 0
                : getBlockNumber()
                    .sub(rewardCoins[rewardCoinSub].blockNumber)
                    .mul(rewardCoins[rewardCoinSub].rewardSpeed)
                    .mul(tokens[account])
                    .div(totalToken);
        value = _getReward(account, coinAddress) + blockReward2;
    }

    /**
     * @dev Extract the current reward in one go
     * @param holder Address of receiver
     */
    function claimToken(address holder, address coinAddress) public {
        require(
            _judgePledgeRate(holder),
            "The current pledge rate does not meet the system pledge rate requirements"
        );
        accuredToken(holder);
        uint256 rewardCoinSub = rewardCoinIndex[coinAddress];
        // uint256 value = stakerStateArray[holder][rewardCoinSub].reward.min(
        //         rewardCoins[rewardCoinSub].rewardTotal
        //     );
        uint256 value = 1;
        require(value > 0, "The reward of address is zero.");

        rewardCoins[rewardCoinSub].coin.transfer(holder, value);
        rewardCoins[rewardCoinSub].rewardTotal = rewardCoins[rewardCoinSub]
            .rewardTotal
            .sub(value);

        stakerStateArray[holder][rewardCoinSub].index = rewardCoins[
            rewardCoinSub
        ]
            .index;
        stakerStateArray[holder][rewardCoinSub].reward = stakerStateArray[
            holder
        ][rewardCoinSub]
            .reward
            .sub(value);

        emit ClaimToken(holder, value, coinAddress);
    }

    /**
     * @dev Get block number now
     */
    function getBlockNumber() public view returns (uint256) {
        return block.number;
    }

    /**
     * @dev Inject token to reward
     * @param amount The number of injecting
     */
    function injectReward(uint256 amount, address coinAddress)
        external
        onlyOwner
    {
        uint256 rewardCoinSub = rewardCoinIndex[coinAddress];
        rewardCoins[rewardCoinSub].coin.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        rewardCoins[rewardCoinSub].rewardTotal = rewardCoins[rewardCoinSub]
            .rewardTotal
            .add(amount);

        emit InjectReward(amount, coinAddress);
    }

    /**
     * @dev Extract token from reward
     * @param account Address of receiver
     * @param amount The number of extracting
     */
    function extractReward(
        address account,
        uint256 amount,
        address coinAddress
    ) external onlyOwner {
        uint256 rewardCoinSub = rewardCoinIndex[coinAddress];

        require(
            amount <= rewardCoins[rewardCoinSub].rewardTotal,
            "withdraw overflow."
        );
        rewardCoins[rewardCoinSub].coin.transfer(account, amount);
        rewardCoins[rewardCoinSub].rewardTotal = rewardCoins[rewardCoinSub]
            .rewardTotal
            .sub(amount);

        emit ExtractReward(account, amount, coinAddress);
    }
}
