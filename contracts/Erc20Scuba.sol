//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;




// Scuba Finance: https://github.com

// Primary Author(s)
// NicoDeva

/*
	This token follows a halving emissions system
	
	A call to mint doesnt actually mint the amount called but the amount times the current multiplier
	Multiplier halves every year 86400 * 365 sec
	So at period 0, amount minted = 50M, then 25M... up to 100M
	50M / 86400 / 365 = 1.5854.... per seconds
	
	Careful: masterchef still needs to call the contract properly without minting too much

*/

import "hardhat/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Erc20Scuba is ERC20, Ownable {
	using SafeERC20 for IERC20;
	
	/// Address of the staking contract allowed to mint new coins
	address public masterdiver;

	/// Time of first mint from which emissions decay
	uint public startDate;

	

	constructor () ERC20('Scuba Finance', 'SCUBA')
	{
		//_mint(msg.sender, 10**8); // 100M supply
		console.log("mint to tebcter");
		_mint(0x1Fc444e3E4C60e864BfBaA25953B42Fa73695Cf8, 1e20);
		masterdiver = msg.sender; // set owner to deployer address, needs to be changed when masterdiver contract is up
		startDate = block.timestamp;
	}


	/// @notice Mints tokens
	/// Mints new tokens based on the emission schedule,
	function emissionMint(address _to, uint _amount )
		public
		onlyOwner
		returns (uint amount)
	{
		require (block.timestamp > startDate, "CANNOT_REVERT_TIME");
		uint periodsElapsed = (block.timestamp - startDate) / 86400 / 365; // get the integer division, period 0 = full
		uint adjustedAmount = _amount / ( 2 ** periodsElapsed );
		_mint(_to, adjustedAmount);
		return adjustedAmount;
	}
	
	
	
	
	/// @notice Can change masterdiver address in case of problem
	function changeMasterchef(address newDiver )
		public 
	{
		require (msg.sender == masterdiver, "UNAUTHORIZED_CHANGE");
		masterdiver = newDiver;
		transferOwnership(newDiver);
	}
	
	function dummy(uint x)
		private
		pure
		returns (uint)
	{
		return x * 2;
	}
		
		
}