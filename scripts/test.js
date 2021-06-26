
async function main() {
  stake_address = '0xaA8D86712a150a4C30FE99ef6451E498d724F8D1'

  const Stake = await ethers.getContractFactory("Stake");
  const stake = await Stake.attach(stake_address)

  // SimpleERC20 = await ethers.getContractFactory("SimpleERC20");
  // const token = await SimpleERC20.attach("0x8c71196DC20D070a0682D2dCe5D9F3ECD2C1E1B9")
  // ONE_TOKEN = ethers.BigNumber.from(10).pow(18);
  // result = await stake.getInputToken(100000000)
  // await token.approve(stake_address, result)
  
  // console.log(result)
  // await stake.stake(100000000)
  await stake.redeem(100000000)

  // const Oracle = await ethers.getContractFactory("Oracle");
  // oracle = await Oracle.attach("0xAf25cEa23219Da55BD10F65cA0d6F606ff5Fa5C9")
  // ONE_COIN = ethers.BigNumber.from(10).pow(6);
  // const currentPrice = 0.028 * ONE_COIN
  // await oracle.poke(currentPrice)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
