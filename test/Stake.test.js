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
    coin_name = await coin.name();
    ONE_COIN = BigNumber.from(10).pow(coin_decimals);
    console.log('stable coin adddress', coin.address);

    // deploy token
    token = await this.SimpleERC20.deploy("STPT", "STPT", 18, BigNumber.from(1000000).mul(BigNumber.from(10).pow(18)))
    token = await token.deployed();
    token_decimals = await token.decimals();
    token_name = await token.name()
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
    oracle = await this.Oracle.deploy(esm.address, dparam.address, token_name + '-' + coin_name);
    oracle = await oracle.deployed();
    oracle_name = await oracle.name()
    console.log('oracle_address', oracle_name, oracle.address)
    
    // deploy stake
    stake = await this.Stake.deploy(esm.address, dparam.address, oracle.address);
    stake = await stake.deployed();
    console.log('stake_address', stake.address)



    // Setup contract

    // Setup stake token && coin
    await stake.setup(token.address, coin.address)

    // Setup whitelist
    await dparam.addWhite([oracle.address,]);

    await coin.addWhite([stake.address,])

    await esm.addWhite([oracle.address,]);

    // when price meet lowstPrice, system will shut down.
    const currentPrice = 0.028 * ONE_COIN
    const stakeRate = 7 * ONE_COIN / currentPrice
    const lowestPrice = 1.5 / stakeRate
    console.log('lowestPrice shutdown', lowestPrice)
    await dparam.setStakeRate(currentPrice)

    await dparam.setFeeRate(1)

  });


  it('stake should succeed', async function () {
    // Oracle poke price  token/usdp
    await oracle.poke(0.02 * ONE_COIN);

    // await token.approve(stake.address)
    coinAmout = ONE_COIN * 100
    tokenAmount = await stake.getInputToken(coinAmout)
    await token.approve(stake.address, tokenAmount)
    await stake.connect(owner).stake(coinAmout)
    expect((await coin.balanceOf(owner.address)).toString()).to.equal(coinAmout.toString())
    await stake.connect(owner).redeem(coinAmout)
  });


  it('system shold shutdown when price too low', async function () {
    await oracle.poke(0.005 * ONE_COIN);
    expect(await esm.isClosed()).to.equal(true)
  });

});