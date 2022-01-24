pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

// import "@openzeppelin/contracts/access/Ownable.sol"; 
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

import "hardhat/console.sol";

import "./VMMPool.sol";
import "./VMMFactory.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";


/// VMM Router and factory creates and references VMM pools
contract VMMRouter is Ownable {
	
	// Factory address for pools deployment
	address public factoryAddress;
	
	// Initial pool version
	uint8 public currentPoolVersion = 1;

	// Once made public 
	bool public isReleased = false;

	address[] public vmmPoolList;
	mapping ( address => address ) public pairToPool;
	mapping ( address => uint ) public poolVersion;

	/// Admin functions
	function release() public onlyOwner {
		isReleased = true;
	}
	
	/// @notice Updates factory contract
	function updateFactory ( address newFactoryAddress, uint poolVersion_ ) 
		public 
		onlyOwner
	{
		require (poolVersion_ > currentPoolVersion, "VERSION_ERROR");
		console.log("factoryAddress = newFactory5Address");
		factoryAddress = newFactoryAddress;
		currentPoolVersion = poolVersion_;
	}
	
	
	/// @notice Get the number of VMM pools
	function getPoolCount() public view returns (uint256 poolCount) {
		return vmmPoolList.length;
	}
	
	
	
	/// @notice Creates a new pool if not existing (with current version)
	function createPool(address swapPair, address swapRouter, string memory amm) 
		public 
		returns (address poolAddress)
	{
		require ( isReleased || msg.sender == owner, "ONLY_OWNER_ALLOWED");
		require ( pairToPool[swapPair] == address(0) || poolVersion[swapPair] < currentPoolVersion, "MARKET_ALREADY_EXISTS" ); 
		
		address newPool = VMMFactory(factoryAddress).createPool(swapPair, swapRouter, amm);
		vmmPoolList.push(newPool);
		pairToPool[swapPair] = newPool;
		poolVersion[newPool] = currentPoolVersion;
		
		return newPool;
	}
	

}