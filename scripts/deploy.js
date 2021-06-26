// scripts/deploy.js

async function main() {
  

  // deploy coin
  Stable = await ethers.getContractFactory("StableCoin");
  coin_decimals = 6
  coin_name = "USDP"
  coin_address = "0x666A987d0137d4972fC19eE81020979D6b5Adc5A"
  ONE_COIN = ethers.BigNumber.from(10).pow(coin_decimals);
  coin = Stable.attach(coin_address)

  // deploy token
  token_decimals = 18
  token_name = "STPT"
  token_address = "0x8c71196DC20D070a0682D2dCe5D9F3ECD2C1E1B9"
  ONE_TOKEN = ethers.BigNumber.from(10).pow(token_decimals);



  // deploy Esm
  const Esm = await ethers.getContractFactory("Esm");
  const esm = await Esm.deploy();
  await esm.deployed();
  console.log("esm:", esm.address);
  // deploy Dparam
  const Dparam = await ethers.getContractFactory("Dparam");
  const dparam = await Dparam.deploy(ethers.BigNumber.from(10).pow(coin_decimals), ethers.BigNumber.from(10).pow(token_decimals));
  await dparam.deployed();
  console.log("dparam:", dparam.address);


  
  // deploy oracle
  const Oracle = await ethers.getContractFactory("Oracle");
  oracle = await Oracle.deploy(esm.address, dparam.address, token_name + '-' + coin_name);
  oracle = await oracle.deployed();
  oracle_name = await oracle.name()
  console.log('oracle:', oracle_name, oracle.address)
  
  // deploy stake
  Stake = await ethers.getContractFactory("Stake");
  stake = await Stake.deploy(esm.address, dparam.address, oracle.address);
  stake = await stake.deployed();
  console.log('stake:', stake.address)

   // Setup stake token && coin
   await stake.setup(token_address, coin_address)

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

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });