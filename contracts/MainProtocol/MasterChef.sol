// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../Tokens/RGN.sol";
import "./interfaces/BaseRewardPool.sol";
import "./interfaces/IBaseRewardPool.sol";

/*
  _____                                ______ _                            
 |  __ \                              |  ____(_)                           
 | |__) |__ _  __ _ _ __   __ _ _ __  | |__   _ _ __   __ _ _ __   ___ ___ 
 |  _  // _` |/ _` | '_ \ / _` | '__| |  __| | | '_ \ / _` | '_ \ / __/ _ \
 | | \ \ (_| | (_| | | | | (_| | |    | |    | | | | | (_| | | | | (_|  __/
 |_|  \_\__,_|\__, |_| |_|\__,_|_|    |_|    |_|_| |_|\__,_|_| |_|\___\___|
               __/ |                                                       
              |___/                                                        
*/

// MasterChefRGN is a boss. He says "go f your blocks lego boy, I'm gonna use timestamp instead".
// And to top it off, it takes no risks. Because the biggest risk is operator error.
// So we make it virtually impossible for the operator of this contract to cause a bug with people's harvests.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once RGN is sufficiently
// distributed and the community can show to govern itself.
//
// Godspeed and may the 10x be with you.

/// @title A contract for managing all reward pools
/// @author Ragnar Team
/// @notice You can use this contract for depositing RGN,RGNYETI, and Liquidity Pool tokens.

contract MasterChefRGN is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 available; // in case of locking
        //
        // We do some fancy math here. Basically, any point in time, the amount of RGNs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRGNPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRGNPerShare` (and `lastRewardTimestamp`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. RGNs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that RGNs distribution occurs.
        uint256 accRGNPerShare; // Accumulated RGNs per share, times 1e12. See below.
        address rewarder;
        address locker;
    }

    // The RGN TOKEN!
    RGN public rgn;

    // RGN tokens created per second.
    uint256 public rgnPerSec;
    
    // Get current rewarder address
    address public rewarderAddress;

    // Info of each pool.
    address[] public registeredToken;

    address public yetiBooster;

    mapping(address => PoolInfo) public addressToPoolInfo;
    // Set of all LP tokens that have been added as pools
    mapping(address => bool) private lpTokens;
    // Info of each user that stakes LP tokens.
    mapping(address => mapping(address => UserInfo)) private userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when RGN mining starts.
    uint256 public startTimestamp;

    bool public realEmergencyAllowed;

    mapping(address => bool) public poolManagers;

    event Add(
        uint256 allocPoint,
        address indexed lpToken,
        IBaseRewardPool indexed rewarder
    );
    event Set(
        address indexed lpToken,
        uint256 allocPoint,
        IBaseRewardPool indexed rewarder,
        bool overwrite
    );
    event Deposit(
        address indexed user,
        address indexed lpToken,
        uint256 amount
    );
    event Withdraw(
        address indexed user,
        address indexed lpToken,
        uint256 amount
    );
    event UpdatePool(
        address indexed lpToken,
        uint256 lastRewardTimestamp,
        uint256 lpSupply,
        uint256 accRGNPerShare
    );
    event Harvest(
        address indexed user,
        address indexed lpToken,
        uint256 amount
    );
    event EmergencyWithdraw(
        address indexed user,
        address indexed lpToken,
        uint256 amount
    );
    event UpdateEmissionRate(address indexed user, uint256 _rgnPerSec);

    function __MasterChefRGN_init(
        address _rgn,
        uint256 _rgnPerSec,
        uint256 _startTimestamp
    ) public initializer {
        __Ownable_init();
        require(_rgnPerSec <= 10**6 * 10**18, "Emission too high");
        rgn = RGN(_rgn);
        _rgnPerSec = _rgnPerSec;
        startTimestamp = _startTimestamp;
        totalAllocPoint = 0;
        poolManagers[owner()] = true;
    }

    /// @notice Returns number of registered tokens, tokens having a registered pool.
    /// @return Returns number of registered tokens
    function poolLength() external view returns (uint256) {
        return registeredToken.length;
    }

    /// @notice Used to give edit rights to the pools in this contract to a Pool Manager
    /// @param _address Pool Manager Adress
    /// @param _bool True gives rights, False revokes them
    function setPoolManagerStatus(address _address, bool _bool)
        external
        onlyOwner
    {
        poolManagers[_address] = _bool;
    }

    function setYetiBooster(address _address) external onlyOwner {
        yetiBooster = _address;
    }

    /// @notice allow the use of realEmergencyWithdraw.
    /// @notice WARNING : the contract should not be used after that action for anything other that withdrawing
    function allowEmergency() external onlyOwner {
        realEmergencyAllowed = true;
    }

    modifier onlyPoolManager() {
        require(poolManagers[msg.sender], "Not a Pool Manager");
        _;
    }

    /// @notice Gives information about a Pool. Used for APR calculation and Front-End
    /// @param token Staking token of the pool we want to get information from
    /// @return emission - Emissions of RGN from the contract, allocpoint - Allocated emissions of RGN to the pool,sizeOfPool - size of Pool, totalPoint total allocation points
    function getPoolInfo(address token)
        external
        view
        returns (
            uint256 emission,
            uint256 allocpoint,
            uint256 sizeOfPool,
            uint256 totalPoint
        )
    {
        PoolInfo memory pool = addressToPoolInfo[token];
        return (
            rgnPerSec,
            pool.allocPoint,
            IERC20(token).balanceOf(address(this)),
            totalAllocPoint
        );
    }
    
    /// @notice Add a new lp to the pool. Can only be called by a PoolManager.
    /// @param _lpToken Staking token of the pool
    /// @param mainRewardToken Token that will be rewarded for staking in the pool
    /// @return address of the rewarder created
    function createRewarder(address _lpToken, address mainRewardToken)
        public
        onlyPoolManager
        returns (address)
    {
        BaseRewardPool _rewarder = new BaseRewardPool(
            _lpToken,
            mainRewardToken,
            address(this),
            msg.sender,
            yetiBooster
        );
        rewarderAddress = address(_rewarder);
        return address(_rewarder);
    }

    /// @notice Add a new pool. Can only be called by a PoolManager.
    /// @param _allocPoint Allocation points of RGN to the pool
    /// @param _lpToken Staking token of the pool
    /// @param _rewarder Address of the rewarder for the pool
    function add(
        uint256 _allocPoint,
        address _lpToken,
        address _rewarder
    ) external onlyPoolManager {
        require(
            Address.isContract(address(_lpToken)),
            "add: LP tkn must be valid cntrt"
        );
        require(
            Address.isContract(address(_rewarder)) ||
                address(_rewarder) == address(0),
            "add: rewarder must be cntrt or 0"
        );
        require(!lpTokens[_lpToken], "add: LP already added");

        massUpdatePools();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp
            ? block.timestamp
            : startTimestamp;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        registeredToken.push(_lpToken);
        addressToPoolInfo[_lpToken] = PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTimestamp: lastRewardTimestamp,
            accRGNPerShare: 0,
            rewarder: _rewarder,
            locker: address(0)
        });
        lpTokens[_lpToken] = true;
        emit Add(_allocPoint, _lpToken, IBaseRewardPool(_rewarder));
    }

    /// @notice Updates the given pool's RGN allocation point, rewarder address and locker address if overwritten. Can only be called by a Pool Manager.
    /// @param _lp Staking token of the pool
    /// @param _allocPoint Allocation points of RGN to the pool
    /// @param _rewarder Address of the rewarder for the pool
    /// @param overwrite If true, the rewarder and locker are overwritten

    function set(
        address _lp,
        uint256 _allocPoint,
        address _rewarder,
        bool overwrite
    ) external onlyPoolManager {
        require(
            Address.isContract(address(_rewarder)) ||
                address(_rewarder) == address(0),
            "set: rewarder must be cntrt or 0"
        );
        massUpdatePools();
        totalAllocPoint =
            totalAllocPoint -
            addressToPoolInfo[_lp].allocPoint +
            _allocPoint;
        addressToPoolInfo[_lp].allocPoint = _allocPoint;
        if (overwrite) {
            addressToPoolInfo[_lp].rewarder = _rewarder;
        }
        emit Set(
            _lp,
            _allocPoint,
            IBaseRewardPool(addressToPoolInfo[_lp].rewarder),
            overwrite
        );
    }

    /// @notice Provides available amount for a specific user for a specific pool.
    /// @param _lp Staking token of the pool
    /// @param _user Address of the user
    /// @return availableAmount Amount available for the user to withdraw if needed

    function depositInfo(address _lp, address _user)
        public
        view
        returns (uint256 availableAmount)
    {
        return userInfo[_lp][_user].available;
    }

    /// @notice View function to see pending tokens on frontend.
    /// @param _lp Staking token of the pool
    /// @param _user Address of the user
    /// @param token Specific pending token, apart from RGN
    /// @return pendingRGN - Expected amount of RGN the user can claim, bonusTokenAddress - token, bonusTokenSymbol - token Symbol,  pendingBonusToken - Expected amount of token the user can claim
    function pendingTokens(
        address _lp,
        address _user,
        address token
    )
        external
        view
        returns (
            uint256 pendingRGN,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        UserInfo storage user = userInfo[_lp][_user];
        uint256 accRGNPerShare = pool.accRGNPerShare;
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
            uint256 rgnReward = (multiplier * rgnPerSec * pool.allocPoint) /
                totalAllocPoint;
            accRGNPerShare = accRGNPerShare + (rgnReward * 1e12) / lpSupply;
        }
        pendingRGN = (user.amount * accRGNPerShare) / 1e12 - user.rewardDebt;

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            (bonusTokenAddress, bonusTokenSymbol) = (
                token,
                IERC20Metadata(token).symbol()
            );
            pendingBonusToken = IBaseRewardPool(pool.rewarder).earned(
                _user,
                token
            );
        }
    }

    /// @notice Update reward variables for all pools. Be mindful of gas costs!
    function massUpdatePools() public {
        uint256 length = registeredToken.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(registeredToken[pid]);
        }
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _lp Staking token of the pool
    function updatePool(address _lp) public {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
        uint256 rgnReward = (multiplier * rgnPerSec * pool.allocPoint) /
            totalAllocPoint;
        pool.accRGNPerShare =
            pool.accRGNPerShare +
            ((rgnReward * 1e12) / lpSupply);
        pool.lastRewardTimestamp = block.timestamp;
        emit UpdatePool(
            _lp,
            pool.lastRewardTimestamp,
            lpSupply,
            pool.accRGNPerShare
        );
    }

    /// @notice Deposits staking token to the pool, updates pool and distributes rewards
    /// @param _lp Staking token of the pool
    /// @param _amount Amount to deposit to the pool
    function deposit(address _lp, uint256 _amount) external {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        IERC20(pool.lpToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        UserInfo storage user = userInfo[_lp][msg.sender];
        updatePool(_lp);
        if (user.amount > 0) {
            // Harvest RGN
            uint256 pending = (user.amount * pool.accRGNPerShare) /
                1e12 -
                user.rewardDebt;
            safeRGNTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _lp, pending);
        }
        user.amount = user.amount + _amount;
        user.available = user.available + _amount;
        user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;

        IBaseRewardPool rewarder = IBaseRewardPool(
            addressToPoolInfo[_lp].rewarder
        );
        if (_amount == 0 && address(rewarder) != address(0)) {
            rewarder.getReward(msg.sender);
        } else {
            if (address(rewarder) != address(0)) {
                rewarder.stakeFor(msg.sender, _amount);
                rewarder.getReward(msg.sender);
            }

            emit Deposit(msg.sender, _lp, _amount);
        }
    }


    /// @notice Deposit LP tokens to MasterChef for RGN allocation, and stakes them on rewarder as well.
    /// @param _lp Staking token of the pool
    /// @param _amount Amount to deposit
    /// @param sender Address of the user 
    function depositFor(
        address _lp,
        uint256 _amount,
        address sender
    ) external {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        UserInfo storage user = userInfo[_lp][sender];
        IERC20(pool.lpToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        updatePool(_lp);
        if (user.amount > 0) {
            // Harvest RGN
            uint256 pending = (user.amount * pool.accRGNPerShare) /
                1e12 -
                user.rewardDebt;
            safeRGNTransfer(sender, pending);
            emit Harvest(sender, _lp, pending);
        }
        user.amount = user.amount + _amount;
        user.available = user.available + _amount;
        user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;

        IBaseRewardPool rewarder = IBaseRewardPool(
            addressToPoolInfo[_lp].rewarder
        );
        if (_amount == 0 && address(rewarder) != address(0)) {
            rewarder.getReward(sender);
        } else {
            if (address(rewarder) != address(0)) {
                rewarder.stakeFor(sender, _amount);
                rewarder.getReward(sender);
            }
            emit Deposit(sender, _lp, _amount);
        }
    }

    /// @notice Claims for each of the pools in the list
    /// @param _lps Staking tokens of the pools we want to claim from
    /// @param userAddress address of user to claim for
    function multiclaim(address[] calldata _lps, address userAddress) external {
        uint256 length = _lps.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            address _lp = _lps[pid];
            PoolInfo storage pool = addressToPoolInfo[_lp];
            UserInfo storage user = userInfo[_lp][userAddress];
            updatePool(_lp);
            if (user.amount > 0) {
                // Harvest RGN
                uint256 pending = (user.amount * pool.accRGNPerShare) /
                    1e12 -
                    user.rewardDebt;
                safeRGNTransfer(userAddress, pending);
                emit Harvest(userAddress, _lp, pending);
            }
            user.amount = user.amount;
            user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;
            if (address(pool.rewarder) != address(0)) {
                IBaseRewardPool rewarder = IBaseRewardPool(pool.rewarder);
                rewarder.getReward(userAddress);
            }
        }
    }

    /// @notice Withdraw LP tokens from MasterChef.
    /// @param _lp Staking token of the pool
    /// @param _amount amount to withdraw
    function withdraw(address _lp, uint256 _amount) external {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        UserInfo storage user = userInfo[_lp][msg.sender];
        require(user.available >= _amount, "withdraw: not good");

        updatePool(_lp);

        // Harvest RGN
        uint256 pending = (user.amount * pool.accRGNPerShare) /
            1e12 -
            user.rewardDebt;
        safeRGNTransfer(msg.sender, pending);
        emit Harvest(msg.sender, _lp, pending);

        user.amount = user.amount - _amount;
        user.available = user.available - _amount;
        user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;

        address rewarder = addressToPoolInfo[_lp].rewarder;
        if (address(rewarder) != address(0)) {
            IBaseRewardPool(rewarder).withdrawFor(msg.sender, _amount, true);
        }

        IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _lp, _amount);
    }

    /// @notice Withdraw LP tokens from MasterChef for a specific user.
    /// @param _lp Staking token of the pool
    /// @param _amount amount to withdraw
    /// @param _sender address of the user to withdraw for
    function withdrawFor(
        address _lp,
        uint256 _amount,
        address _sender
    ) external {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        UserInfo storage user = userInfo[_lp][_sender];
        require(user.available >= _amount, "withdraw: not good");

        updatePool(_lp);

        // Harvest RGN
        uint256 pending = (user.amount * pool.accRGNPerShare) /
            1e12 -
            user.rewardDebt;
        safeRGNTransfer(_sender, pending);
        emit Harvest(_sender, _lp, pending);

        user.amount = user.amount - _amount;
        user.available = user.available - _amount;
        user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;

        address rewarder = addressToPoolInfo[_lp].rewarder;
        if (address(rewarder) != address(0)) {
            IBaseRewardPool(rewarder).withdrawFor(_sender, _amount, true);
        }
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        emit Withdraw(_sender, _lp, _amount);
    }

    /// @notice Withdraw all available tokens without caring about rewards. EMERGENCY ONLY.
    /// @param _lp Staking token of the pool
    /// @dev withdrawFor of the rewarder with the third param at false is an emergency withdraw
    function emergencyWithdraw(address _lp) external {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        UserInfo storage user = userInfo[_lp][msg.sender];
        address rewarder = addressToPoolInfo[_lp].rewarder;
        uint256 amount = user.available;
        user.available = 0;
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _lp, amount);
        user.amount = user.amount - amount;
        user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;
        if (address(rewarder) != address(0)) {
            IBaseRewardPool(rewarder).withdrawFor(msg.sender, amount, false);
        }
    }

    /// @notice Withdraw all available tokens, trying to get rewards
    /// @notice in caise of failure, use emergencyWithdraw
    /// @param _lp Staking token of the pool
    function emergencyWithdrawWithReward(address _lp) external {
        PoolInfo storage pool = addressToPoolInfo[_lp];
        UserInfo storage user = userInfo[_lp][msg.sender];
        uint256 amount = user.available;
        user.available = 0;
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _lp, amount);
        user.amount = user.amount - amount;
        user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;
        address rewarder = addressToPoolInfo[_lp].rewarder;
        if (address(rewarder) != address(0)) {
            IBaseRewardPool(rewarder).withdrawFor(msg.sender, amount, true);
        }
    }

    /// @notice In the highly unlikely case of a fail of rewarder.withdrawFor, this emergency withdraw will work
    /// @notice if this function is used, the rewarder state will be wrong. REAL EMERGENCY ONLY
    /// @param _lp Staking token of the pool
    function realEmergencyWithdraw(address _lp) external {
        require(realEmergencyAllowed, "Real em allowed if emWith fails");
        PoolInfo storage pool = addressToPoolInfo[_lp];
        UserInfo storage user = userInfo[_lp][msg.sender];
        uint256 amount = user.available;
        user.available = 0;
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _lp, amount);
        user.amount = user.amount - amount;
        user.rewardDebt = (user.amount * pool.accRGNPerShare) / 1e12;
    }

    // Safe rgn transfer function, just in case if rounding error causes pool to not have enough RGNs.
    function safeRGNTransfer(address _to, uint256 _amount) internal {
        rgn.mint(address(this), _amount);
        uint256 rgnBal = rgn.balanceOf(address(this));
        if (_amount > rgnBal) {
            rgn.transfer(_to, rgnBal);
        } else {
            rgn.transfer(_to, _amount);
        }
    }

    /// @notice Update the emission rate of RGN for MasterChef
    /// @param _rgnPerSec new emission per second
    function updateEmissionRate(uint256 _rgnPerSec) public onlyOwner {
        require(_rgnPerSec <= 10**6 * 10**18, "Emission too high");
        massUpdatePools();
        rgnPerSec = _rgnPerSec;
        emit UpdateEmissionRate(msg.sender, _rgnPerSec);
    }
}
