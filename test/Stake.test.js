const { BigNumber } = require('@ethersproject/bignumber');
const { expect} = require('chai');

const chai = require('chai');
const { solidity } = require('ethereum-waffle');

chai.use(solidity);

// // Test Stake
describe('Test Stake', function () {

  before(async function () {
    [owner, user] = await ethers.getSigners();

    this.Esm = await ethers.getContractFactory("Esm");
    this.Dparam = await ethers.getContractFactory("Dparam");
    this.Oracle = await ethers.getContractFactory("Oracle");
    this.Stake = await ethers.getContractFactory("Stake");
    this.Stable = await ethers.getContractFactory("StableCoin");
    this.SimpleERC20 = await ethers.getContractFactory("SimpleERC20");
    

    //  Init contract
    // deploy stable coin
    coin = await this.Stable.deploy("USDSP", "USDP", 6);
    coin = await coin.deployed();
    coin_decimals = await coin.decimals();
    ONE_COIN = BigNumber.from(10).pow(coin_decimals);
    console.log('stable coin adddress', coin.address);

    // deploy token
    token = await this.SimpleERC20.deploy("STPT", "STPT", 18, BigNumber.from(1000000).mul(BigNumber.from(10).pow(18)))
    token = await token.deployed();
    token_decimals = await token.decimals();
    ONE_TOKEN = BigNumber.from(10).pow(token_decimals);
    console.log('token adddress', token.address);


    // deploy Esm
    esm = await this.Esm.deploy();
    esm = await esm.deployed();
    console.log('esm_address', esm.address)

    // deploy Dparam
    dparam = await this.Dparam.deploy(BigNumber.from(10).pow(coin_decimals), BigNumber.from(10).pow(token_decimals));
    dparam = await dparam.deployed();
    console.log('dparam_address', dparam.address)

    // deploy oracle
    oracle = await this.Oracle.deploy(esm.address, dparam.address);
    oracle = await oracle.deployed();
    console.log('oracle_address', oracle.address)
    
    // deploy stake
    stake = await this.Stake.deploy(esm.address, dparam.address, oracle.address);
    stake = await stake.deployed();
    console.log('stake_address', stake.address)



    // Setup contract
    // Setup stake address in esm
    await esm.setupTokenStake(stake.address)

    // Setup stake token && coin
    await stake.setup(token.address, coin.address)

    // Setup whitelist
    await dparam.addWhite([oracle.address,]);

    await coin.addWhite([stake.address,])

    await esm.addWhite([oracle.address,]);

    // Oracle poke price  token/usdt
    await oracle.poke(10000);

    await dparam.setFeeRate(1)

  });



  // it('stake should failed when coinAmount less than minMint', async function () {
  //   await expect(stake.stake(100)).to.revertedWith("First make coin must grater than 100.");
  // });


  it('stake should succeed', async function () {
    // await token.approve(stake.address)
    coinAmout = ONE_COIN * 100
    tokenAmount = await stake.getInputToken(coinAmout)
    await token.approve(stake.address, tokenAmount)
    await stake.connect(owner).stake(coinAmout)
    expect((await coin.balanceOf(owner.address)).toString()).to.equal(coinAmout.toString())

    result = await stake.debtOf(owner.address)
    console.log(result)
  });


});