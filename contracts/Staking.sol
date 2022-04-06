// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;


import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";



/**
 * StakingRewards contract allows staking SCUBA to earn rewards and emissions
 * Tokens are locked for a varying amount of time ()
 */
contract Staking is ReentrancyGuard {

	//Governance token staked
	ERC20 public tokenAddress;

	// Stakers balance
	mapping (address => uint) public stakeBalance;
	
	// Stakers weights 
	mapping (address => uint) public stakeWeight;
	
	// Stakes unlock
	mapping (address => uint) public stakeUnlockDate;
	
	// Stake RewardDebt
	// Inspired from masterchef: keep track of what share of the pool user is not eligible for (already clained + uneligible on first lockup)
	mapping (address => uint) private stakeDebt;
	
	// Total weights
	uint public totalWeight;
	
	// Total deposits: keep track of deposits since 
	uint public totalDeposits;
	
	// Minimum lockup: 1 week maximum 4y
	uint public MINIMUM_LOCKUP = 604800; // 1 week
	uint public MAXIMUM_LOCKUP = 126144000; // 1 week
	
	
	constructor (ERC20 _tokenAddress ){
		tokenAddress = _tokenAddress;
	}
	
	
	
	/* ========== FUNCTIONS ========== */
	
	/*
	function balanceOf (address account) public view returns (uint)
	{
		return stakeBalance[account];
	}
	
	
	function weightOf ( address account ) public view returns (uint)
	{
		return stakeWeight[account];
	}*/
	
	
	function pendingRewards (address account ) public view returns (uint)
	{
		if ( totalWeight == 0 ) return 0;
		return tokenSurplus()  *stakeWeight[account] / totalWeight - stakeDebt[account];
	}
	
	/// @notice Returns the total pool rewards waiting to be claimed, i.e current balance - totalDeposits
	function tokenSurplus() public view returns (uint)
	{
		return ERC20(tokenAddress).balanceOf(address(this)) - totalDeposits;
	}
	
	
	/// @notice Stake some tokens
	/// @param amount Amount staked
	/// @param lockup Lockup duration in seconds
	function stake(uint amount, uint lockup)
		external 
		nonReentrant 
	{
		require ( lockup < MAXIMUM_LOCKUP, "LOCKUP_CANNOT_EXCEED_4_YEARS_");
		claimRewards(msg.sender);
		
		uint newAmount = amount;
		uint newLockup = lockup;
		
		//Merge with previous existing stake: average lockup, recalculate weight
		if ( stakeBalance[msg.sender] > 0 ){
			console.log("Already some balance %s", stakeBalance[msg.sender]);
			newAmount = amount + stakeBalance[msg.sender];
			uint oldLockup = 0;
			if ( stakeUnlockDate[msg.sender] > block.timestamp ) oldLockup = stakeUnlockDate[msg.sender] - block.timestamp;
			newLockup = ( oldLockup * stakeBalance[msg.sender] + amount * lockup ) / (amount + stakeBalance[msg.sender] );
		}
		if ( newLockup < MINIMUM_LOCKUP ) newLockup = MINIMUM_LOCKUP;

		uint newWeight = calculateWeight( newAmount, newLockup );
		
		uint oldWeight = stakeWeight[msg.sender];
		totalWeight = totalWeight + newWeight - oldWeight;
		stakeWeight[msg.sender] = newWeight;
		stakeBalance[msg.sender] = newAmount;
		stakeUnlockDate[msg.sender] = block.timestamp + newLockup;
		ERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
		totalDeposits += amount;
		
		stakeDebt[msg.sender] = tokenSurplus()*newWeight/totalWeight;
	}
	
	
	/// @notice Withdraw user stake if not locked
	/// @param amount Amount to withdraw 
	function withdraw (uint amount) 
		external
		nonReentrant 
	{
		require ( amount <= stakeBalance[msg.sender], "INSUFFICIENT_FUNDS");
		require ( stakeUnlockDate[msg.sender] <= block.timestamp, "FUNDS_LOCKED");
		
		claimRewards(msg.sender);
		
		if (amount > 0){
			//in case of withdraw the new lockup is 0
			uint newWeight = calculateWeight(stakeBalance[msg.sender] - amount, 0);
			totalWeight = totalWeight + newWeight - stakeWeight[msg.sender];
			
			stakeWeight[msg.sender] = newWeight;
			stakeBalance[msg.sender] -= amount;
			
			ERC20(tokenAddress).transfer(msg.sender, amount);
			totalDeposits -= totalDeposits;
		}
	}
	
	/// @notice Withdraw all without time verification, internal used for 
	
	
	/// @notice Extends the lockup to (now + lockup), obvs needs to be further than current lock
	function relock(uint duration)
		public
		nonReentrant
	{
		claimRewards(msg.sender);
		
		uint previousLockup = 0;
		if ( block.timestamp < stakeUnlockDate[msg.sender] ) previousLockup = stakeUnlockDate[msg.sender] - block.timestamp;
		uint newLockup = previousLockup + duration;
		require ( newLockup < MAXIMUM_LOCKUP, "LOCKUP_CANNOT_EXCEED_4_YEARS" );

		uint newWeight = calculateWeight(stakeBalance[msg.sender], newLockup);
		
		totalWeight = totalWeight + newWeight - stakeWeight[msg.sender];
		stakeWeight[msg.sender] = newWeight;
		stakeUnlockDate[msg.sender] = block.timestamp + newLockup;
		
	}

	
	/// @notice Calculates the weight of a stake based on amount locked
	function calculateWeight(uint amount, uint lockDurationInSeconds) private pure returns (uint)
	{
		// The time weight is the (years^2)/10 + 1, eg:
		// 1 week ~ 0.02y 0.02*0.02/10 + 1 -> 1.00004 
		// 4years -> 4*4/10 +1 -> 2.6
		uint yearsE9 = lockDurationInSeconds * 1e9 / 86400 / 365;
		uint timeWeightE18 = yearsE9 * yearsE9 / 10 + 1;
		uint weight = amount * timeWeightE18 / 1e18;
		
		return weight;
	}
	

	/// @notice Updates and transfers owed user rewards 
	/// Since claiming changes the ratio of user balances we can either keep track of deposits and calculate claims based on token surplus
	/// or handle each clain as a withdrawal followed by a lock of the originally locked amount for the remaining time, but that'd make 1 extra transfer
	function claimRewards(address account) public 
		returns (uint)
	{
		// We give an account its underlying share minus its reward debt, then update reward debt so that pending is 0
		// We also update weight since time has elapsed
		if ( stakeBalance[account] > 0 ){
			uint previousWeight = stakeWeight[account];
			// User gets a weighted share of the token surplus (total balance - totalDeposits) minus his debt
			uint pending = tokenSurplus() * previousWeight / totalWeight - stakeDebt[account];
			
			// update stake status: new weight, new stakeDebt
			uint newLockup = 0;
			if ( block.timestamp < stakeUnlockDate[account] ) newLockup = stakeUnlockDate[account] - block.timestamp;
			uint newWeight = calculateWeight(stakeBalance[account], newLockup);
			
			stakeWeight[account] = newWeight;
			totalWeight = totalWeight + newWeight - previousWeight;
			// First transfer pending rewards out, then reset debt based on new balance
			ERC20(tokenAddress).transfer(account, pending);
			stakeDebt[account] = tokenSurplus() * previousWeight / totalWeight; //reset rewards
			
			return pending;
		}
		return 0;
	}
}