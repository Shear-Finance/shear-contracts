// deploy/00_deploy_your_contract.js

const { ethers } = require("hardhat");

const localChainId = "31337";

// const sleep = (ms) =>
//   new Promise((r) =>
//     setTimeout(() => {
//       console.log(`waited for ${(ms / 1000).toFixed(3)} seconds`);
//       r();
//     }, ms)
//   );


module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  
  const devAccountAddress = "0x1Fc444e3E4C60e864BfBaA25953B42Fa73695Cf8"
  
  await deploy("Erc20Scuba", {
    from: deployer,
    args: [],
    log: true,
    waitConfirmations: 1,
	skipIfAlreadyDeployed: false,
  })
  const Erc20Scuba = await ethers.getContract("Erc20Scuba", deployer)
    


  await deploy("Staking", {
    from: deployer,
    args: [Erc20Scuba.address],
    log: true,
    waitConfirmations: 1,
	skipIfAlreadyDeployed: false,
  })
  const Staking = await ethers.getContract("Staking", deployer)
  
  
	
  await deploy("MasterDiver", {
    from: deployer,
    args: [Erc20Scuba.address, devAccountAddress, devAccountAddress, Staking.address],
    log: true,
    waitConfirmations: 1,
	skipIfAlreadyDeployed: false,
  })
  const MasterDiver = await ethers.getContract("MasterDiver", deployer)
  try {
	await Erc20Scuba.changeMasterchef(MasterDiver.address);
  }
  catch(e) { } // could fail if already deployed





  await deploy("VMMFactory", {
    from: deployer,
    log: true,
    waitConfirmations: 1,
  })
  const VMMFactory = await ethers.getContract("VMMFactory", deployer)
  
  
  
  await deploy("VMMRouter", {
    from: deployer,
    log: true,
    waitConfirmations: 1,
  });
  const VMMRouter = await ethers.getContract("VMMRouter", deployer);
  try {
	await VMMRouter.updateFactory(VMMFactory.address);
  }
  catch(e){
	  console.log("VMMRouter couldnt change factory address")
  }
  

  console.log("Step 1")
  const usdcDaiUniPair = "0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5";
  const uniRouter = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  try {
	await VMMRouter.updatePool(usdcDaiUniPair, uniRouter, "UNI");
	const newPool = await VMMRouter.pairToPool(usdcDaiUniPair) ;
	await MasterDiver.add(100, newPool, false) //add pool in masterchef, pool number 0 baby
  }
  catch(e) { console.log("Couldnt create new pool maybe didnt redeploy", e)  }
  
  
  console.log("Step 2")
  // Deploy a pool to get ABI updated
  await deploy("VMMPool", {
    // Learn more about args here: https://www.npmjs.com/package/hardhat-deploy#deploymentsdeploy
    from: deployer,
    args: ["0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", "VMM-SA-ASD", "UNI", "PLI-PLOP"],
    log: true,
    waitConfirmations: 5,
  })
  console.log("Step 3")
  const DummyPool = await ethers.getContract("VMMPool", deployer)
  
  console.log("Step 4")
  // Getting a previously deployed contract
  const usdcDaiVmmPool = await VMMRouter.pairToPool(usdcDaiUniPair);
  const VMMPool = await ethers.getContractAt("VMMPool", usdcDaiVmmPool);
  
  // Changing ownerships to dev for testing
  //await VMMRouter.transferOwnership(devAccountAddress);



  /*
  //If you want to send value to an address from the deployer
  const deployerWallet = ethers.provider.getSigner()
  await deployerWallet.sendTransaction({
    to: "0x34aA3F359A9D614239015126635CE7732c18fDF3",
    value: ethers.utils.parseEther("0.001")
  })
  */

  /*
  //If you want to send some ETH to a contract on deploy (make your constructor payable!)
  const yourContract = await deploy("YourContract", [], {
  value: ethers.utils.parseEther("0.05")
  });
  */

  /*
  //If you want to link a library into your contract:
  // reference: https://github.com/austintgriffith/scaffold-eth/blob/using-libraries-example/packages/hardhat/scripts/deploy.js#L19
  const yourContract = await deploy("YourContract", [], {}, {
   LibraryName: **LibraryAddress**
  });
  */

  // Verify from the command line by running `yarn verify`

  // You can also Verify your contracts with Etherscan here...
  // You don't want to verify on localhost
  // try {
  //   if (chainId !== localChainId) {
  //     await run("verify:verify", {
  //       address: YourContract.address,
  //       contract: "contracts/YourContract.sol:YourContract",
  //       contractArguments: [],
  //     });
  //   }
  // } catch (error) {
  //   console.error(error);
  // }
};
module.exports.tags = ["VMMRouter", "VMMPool", "Erc20Scuba", "MasterDiver"];
