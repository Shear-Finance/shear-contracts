// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./Erc20Scuba.sol";

// MasterDiver is the distributor
// Staking pools are created that receive a share of the SCUBA token inflation
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once the community can show to govern itself.
//

contract MasterDiver is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // At any point in time, the amount of Scubas
        // entitled to a user but is pending to be distributed is his share, minus what he perceived already
		// When first depositing, consider he perceived what his share would otherwise get him
        //
        //   pending reward = (user.amount * pool.accScubaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accScubaPerShare` (and `lastRewardDate`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

	// Share multiplier for precision
	uint SHARE_MULTIPLIER = 1e12;
	
    // Info of each pool.
    struct PoolInfo {
        ERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. Scubas to distribute per second.
        uint256 lastRewardDate;  // Last block number that Scubas distribution occurs.
        uint256 accScubaPerShare;   // Accumulated Scubas per share, times SHARE_MULTIPLIER. See below.
    }

    // The Scuba TOKEN!
    Erc20Scuba public Scuba;
	
    // Dev address.
    address public devaddr;
	
    // Scuba tokens created per second: yearly halving curve handled by erc20scuba contract, here is basis point
	// 50M*1e18 / 6400 / 365 
    uint256 public scubaPerSecond = uint(50000000).mul(1e18).div(86400).div(365);
	
    // Treasury Fee address
    address public treasuryAddress;
	
    // Founder Fee address
    address public founderAddress;
	
    // Staking Contract address
    address public stakingAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
	
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
	
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
	
    // The date number when Scuba mining starts.
    uint256 public startDate;


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetTreasuryAddress(address indexed user, address indexed newAddress);


	/// @notice Constructor
    constructor(
        Erc20Scuba _scuba,
        address _founderAddress,
        address _treasuryAddress,
        address _stakingAddress
    )
	{
		console.log("d_founderAddress");
        Scuba = _scuba;
        founderAddress = _founderAddress;
        treasuryAddress = _treasuryAddress;
		stakingAddress = _stakingAddress;
    }



    function setStartDate(uint256 _startDate) public onlyOwner {
        require(startDate == 0, "already started!");
        require(_startDate > block.timestamp + 200, "start block has to be further in the future");
        startDate= _startDate;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }


    mapping(ERC20 => uint) public poolId;
    mapping(ERC20 => bool) public poolExistence;
    modifier nonDuplicated(ERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated-");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, ERC20 _lpToken, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardDate = block.timestamp > startDate? block.timestamp : startDate;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
			lpToken : _lpToken,
			allocPoint : _allocPoint,
			lastRewardDate : lastRewardDate,
			accScubaPerShare : 0
        }));
		poolId[_lpToken] = poolInfo.length - 1;
    }

    // Update the given pool's Scuba allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }



    // @notice View function to see pending rewards on frontend.
    function pendingScuba(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accScubaPerShare = pool.accScubaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardDate && lpSupply != 0) {
			uint duration = block.timestamp.sub(pool.lastRewardDate);
            uint256 scubaReward = duration.mul(scubaPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accScubaPerShare = accScubaPerShare.add(scubaReward.mul(SHARE_MULTIPLIER).div(lpSupply));
        }
        return user.amount.mul(accScubaPerShare).div(SHARE_MULTIPLIER).sub(user.rewardDebt);
    }


    // @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // @notice Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp<= pool.lastRewardDate) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardDate = block.timestamp;
            return;
        }

		uint duration = block.timestamp.sub(pool.lastRewardDate);
        uint256 scubaReward = duration.mul(scubaPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        Scuba.emissionMint(treasuryAddress, scubaReward.div(20)); //5% founder, 5% treasury, 10% token holders, 90% LP
        Scuba.emissionMint(founderAddress, scubaReward.div(20));
        Scuba.emissionMint(stakingAddress, scubaReward.div(10));
        uint actualRewardReceived = Scuba.emissionMint(address(this), scubaReward.mul(8).div(10));
		
        pool.accScubaPerShare = pool.accScubaPerShare.add(actualRewardReceived.mul(SHARE_MULTIPLIER).div(lpSupply));
        pool.lastRewardDate = block.timestamp;
    }



    /// @notice Deposit LP tokens to MasterChef for farming allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accScubaPerShare).div(SHARE_MULTIPLIER).sub(user.rewardDebt);
            if (pending > 0) {
                safeScubaTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accScubaPerShare).div(SHARE_MULTIPLIER);
        emit Deposit(msg.sender, _pid, _amount);
    }


    /// @notice Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accScubaPerShare).div(SHARE_MULTIPLIER).sub(user.rewardDebt);
        if (pending > 0) {
            safeScubaTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.transfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accScubaPerShare).div(SHARE_MULTIPLIER);
        emit Withdraw(msg.sender, _pid, _amount);
    }


    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.transfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
		
    }


    /// @notice Safe token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeScubaTransfer(address _to, uint256 _amount) internal {
        uint256 ScubaBal = Scuba.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > ScubaBal) {
            transferSuccess = Scuba.transfer(_to, ScubaBal);
        } else {
            transferSuccess = Scuba.transfer(_to, _amount);
        }
        require(transferSuccess, "safeScubaTransfer: transfer failed");
    }


    /// @notice Update dev address by the previous dev.
    function dev(address _founderAddress) public {
        require(msg.sender == founderAddress, "dev: wut?");
        founderAddress = _founderAddress;
    }

	/// @notice Set treasury address
    function setTreasuryAddress(address _treasuryAddress) public {
        require(msg.sender == treasuryAddress, "setTreasuryAddress: FORBIDDEN");
        treasuryAddress = _treasuryAddress;
        emit SetTreasuryAddress(msg.sender, _treasuryAddress);
    }

}