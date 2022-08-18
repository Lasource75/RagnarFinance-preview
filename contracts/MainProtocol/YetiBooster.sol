// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/OwnableUpgradeable.sol";
import "./interfaces/IFarm.sol";
import "./interfaces/IveYETI.sol";
import "./interfaces/IStabilityPool.sol";
import "./interfaces/IBaseRewardPool.sol";
import "./interfaces/IMintableERC20.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IRGNYeti.sol";
import "./interfaces/MintableERC20.sol";
import "./interfaces/IYetiController.sol";
import "./interfaces/MathUtil128.sol";
import "./interfaces/MathUtil.sol";
import "./interfaces/IRewarderVeYeti.sol";

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

library ERC20FactoryLib {
    function createERC20(string memory name_, string memory symbol_)
        public
        returns (address)
    {
        ERC20 token = new MintableERC20(name_, symbol_);
        return address(token);
    }
}

/// @title YetiBooster
/// @author Ragnar Team
/// @notice YetiBooster is the contract that interacts with ALL Yeti Finance contract
/// @dev the owner of this contract holds a lot of power, and should be owned by a multisig
contract YetiBooster is Initializable, OwnableUpgradeable {
    using MathUtil for uint256;
    using MathUtil128 for uint128;
    using SafeERC20 for IERC20;

    // Addresses
    address public staking_veyeti;
    address public yeti;
    address public rgnYETI;
    address public stakeLpCurve;
    address public masterChef;
    address public yusd;
    address public stabilitypool;
    address public controller;
    address public rewarderVeYeti;

    // Struct of a pool
    struct Pool {
        bool isActive;
        address lpAddress;
        uint256 sizeLp;
        address receiptToken;
        address rewarder;
        bool stabilitypool;
        address addressPool;
    }

    // Fees
    struct Fees {
        uint256 max_value;
        uint256 min_value;
        uint256 value;
        address to;
        bool isYETI;
        bool isAddress;
        bool isActive;
    }

    Fees[] public feeInfos;
    address public veYETIFee;

    uint256 constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE = 2000;
    uint256 public CALLER_FEE;
    uint256 public constant MAX_CALLER_FEE = 500;
    uint256 public totalFee;

    // Yeti data struct
    struct Snapshots {
        mapping(address => uint256) S;
        uint256 P;
        uint256 G;
        uint128 scale;
        uint128 epoch;
    }

    // Variable YETI
    uint256 public constant SCALE_FACTOR = 1e9;
    uint256 public constant DECIMAL_PRECISION = 1e18;

    mapping(address => Pool) public pools;

    // Yeti mappings
    mapping(address => uint256) public deposits;
    mapping(address => Snapshots) public depositSnapshots;

    // Events
    event AddFee(address to, uint256 value, bool isYETI, bool isAddress);
    event SetFee(address to, uint256 value);
    event RemoveFee(address to);

    event NewDeposit(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event NewWithdraw(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event PoolAdded(address tokenAddress);
    event NewYetiStaked(uint256 amount);
    event YetiHarvested(uint256 amount, uint256 callerFee);
    event RewardPaidTo(address to, address rewardToken, uint256 feeAmount);

    // Init
    function __YetiBooster_init(
        address _yeti,
        address _staking_veyeti,
        address _masterChef,
        address _controllerAddress,
        address _stabilitypool,
        address _yusd,
        address _rewarderVeYeti
    ) public initializer {
        __Ownable_init();
        staking_veyeti = _staking_veyeti;
        yeti = _yeti;
        masterChef = _masterChef;
        controller = _controllerAddress;
        stabilitypool = _stabilitypool;
        yusd = _yusd;
        rewarderVeYeti = _rewarderVeYeti;
    }

    function setRGNYETI(address _RGNYETI) external onlyOwner {
        require(rgnYETI == address(0), "rgnYETI already set");
        rgnYETI = _RGNYETI;
    }


    /// @notice Allow to add fees to Ragnar Finance
    /// @dev The value of the fee must match the max fee requirement
    /// @param max The maximum value for that fee
    /// @param min The minimum value for that fee
    /// @param value The initial value for that fee
    /// @param to The address or contract that receives the fee
    /// @param isYETI True if the fee is sent as YETI, otherwise it will be rgnYETI
    /// @param isAddress True if the receiver is an address, otherwise it's a BaseRewarder
    function addFee(
        uint256 max,
        uint256 min,
        uint256 value,
        address to,
        bool isYETI,
        bool isAddress,
        bool isVeYETI
    ) external onlyOwner {
        require(totalFee + value <= MAX_FEE, "Max fee reached");
        require(min <= value && value <= max, "Value not in range");
        feeInfos.push(
            Fees({
                max_value: max,
                min_value: min,
                value: value,
                to: to,
                isYETI: isYETI,
                isAddress: isAddress,
                isActive: true
            })
        );
        if (isVeYETI) {
            veYETIFee = to;
        }
        totalFee += value;
        emit AddFee(to, value, isYETI, isAddress);
    }

    /// @notice Change the value of some fee
    /// @dev The value must be between the min and the max specified when registering the fee
    /// @dev The value must match the max fee requirements
    /// @param index The index of the fee in the fee list
    /// @param value The new value of the fee
    function setFee(uint256 index, uint256 value) external onlyOwner {
        Fees storage fee = feeInfos[index];
        require(fee.isActive, "Non-active fee");
        require(
            fee.min_value <= value && value <= fee.max_value,
            "Value not in range"
        );
        require(totalFee + value - fee.value <= MAX_FEE, "Max fee reached");
        totalFee = totalFee - fee.value + value;
        fee.value = value;
        emit SetFee(fee.to, value);
    }

    /// @notice Remove some fee
    /// @param index The index of the fee in the fee list
    function removeFee(uint256 index) external onlyOwner {
        Fees storage fee = feeInfos[index];
        totalFee -= fee.value;
        fee.isActive = false;
        emit RemoveFee(fee.to);
    }

    /// @notice Set the caller fee
    /// @param value The value of the caller fee
    function setCallerFee(uint256 value) external onlyOwner {
        require(value <= MAX_CALLER_FEE, "Value too high");
        // Check if the fee delta does not make the total fee go over the limit
        totalFee = totalFee + value - CALLER_FEE;
        require(totalFee <= MAX_FEE, "MAX Fee reached");
        CALLER_FEE = value;
    }

    /// @notice Deposit of Stable / Lp Curve on Yeti
    /// @param lptoken The token has deposit
    /// @param amount The number of tokens has deposit
    /// @param sender The user's address
    function deposit(
        address lptoken,
        uint256 amount,
        address sender
    ) external {
        // Get data of the pool
        Pool storage poolInfo = pools[lptoken];
       
        require(poolInfo.isActive, "Pool not active");
        
        if (poolInfo.stabilitypool == true) {

            if (poolInfo.sizeLp > 0) {
                harvest(lptoken);
            }
            // A deposit was made on the stability pools
            IERC20(lptoken).safeTransferFrom(sender, address(this), amount);
            IERC20(lptoken).approve(stabilitypool, amount);
            IStabilityPool(stabilitypool).provideToSP(amount);

            // We get the data as yeti from the user and update it
            (address[] memory assets, uint256[] memory amounts) = getDepositorGains(sender);
            uint256 compoundedYUSDDeposit = getCompoundedYUSDDeposit(sender);
            uint256 newDeposit = compoundedYUSDDeposit.add(amount);
            _updateDepositAndSnapshots(sender, newDeposit);

            // Collateral rewards are sent to the user
            _sendGainsToDepositor(sender, assets, amounts);
            
            // We send a fake token to masterchef to manage the rewards in RGN
            IMintableERC20(poolInfo.receiptToken).mint(address(this), amount);
            IERC20(poolInfo.receiptToken).approve(masterChef, amount);
            IMasterChef(masterChef).depositFor(
                poolInfo.receiptToken,
                amount,
                sender
            );
            poolInfo.sizeLp += amount;
            emit NewDeposit(sender, lptoken, amount);
        } else {
            if (poolInfo.sizeLp > 0) {
                harvest(lptoken);
            }
            IERC20(lptoken).safeTransferFrom(sender, address(this), amount);
            IERC20(lptoken).approve(poolInfo.addressPool, amount);
            IFarm(poolInfo.addressPool).deposit(amount);
            IMintableERC20(poolInfo.receiptToken).mint(address(this), amount);
            IERC20(poolInfo.receiptToken).approve(masterChef, amount);
            IMasterChef(masterChef).depositFor(
                poolInfo.receiptToken,
                amount,
                sender
            );
            poolInfo.sizeLp += amount;
            emit NewDeposit(sender, lptoken, amount);
        }
    }

    /// @notice Withdraw of Stable / Lp Curve on Yeti
    /// @param lptoken The token has withdraw
    /// @param amount The number of tokens
    /// @param sender The user's address
    function withdraw(
        address lptoken,
        uint256 amount,
        address sender
    ) external {
        // Get data of the pool
        Pool storage poolInfo = pools[lptoken];

        require(poolInfo.isActive, "Pool not active");

        if (poolInfo.stabilitypool == true) {
            uint256 initialDeposit = deposits[sender];
            _requireUserHasDeposit(initialDeposit);
            harvest(lptoken);


            // We get the data as yeti from the user and update it
            (address[] memory assets, uint256[] memory amounts) = getDepositorGains(sender);
            uint256 compoundedYUSDDeposit = getCompoundedYUSDDeposit(sender);
            uint256 YUSDtoWithdraw = MathUtil.min(
                amount,
                compoundedYUSDDeposit
            );

            // Withdraw on stabilitypools
            IMasterChef(masterChef).withdrawFor(poolInfo.receiptToken, YUSDtoWithdraw, sender);
            IMintableERC20(poolInfo.receiptToken).burn(address(this), YUSDtoWithdraw);
            IERC20(lptoken).approve(stabilitypool, YUSDtoWithdraw);
            IStabilityPool(stabilitypool).withdrawFromSP(YUSDtoWithdraw);
            // Collateral rewards and yusd are sent to the user
            IERC20(yusd).safeTransfer(sender, YUSDtoWithdraw);
            _sendGainsToDepositor(sender, assets, amounts);

            // We update the data
            uint256 newDeposit = compoundedYUSDDeposit.sub(YUSDtoWithdraw);
            _updateDepositAndSnapshots(sender, newDeposit);
            poolInfo.sizeLp -= amount;
            emit NewWithdraw(sender, lptoken, amount);
        } else {
            harvest(lptoken);
            IMasterChef(masterChef).withdrawFor(poolInfo.receiptToken, amount, sender);
            IMintableERC20(poolInfo.receiptToken).burn(address(this), amount);
            IERC20(lptoken).approve(poolInfo.addressPool, amount);
            IFarm(poolInfo.addressPool).withdraw(amount);
            IERC20(lptoken).safeTransfer(sender, amount);
            IERC20(poolInfo.receiptToken).approve(masterChef, amount);
            poolInfo.sizeLp -= amount;
            emit NewWithdraw(sender, lptoken, amount);
        }
    }
    
    /// @notice harvest a pool from Yeti Finance
    /// @param lptoken the address of the token to harvest
    function harvest(address lptoken) public {
        Pool storage poolInfo = pools[lptoken];

        require(poolInfo.isActive, "Pool not active");
        if (poolInfo.stabilitypool == true) {
            uint256 beforeBalance = IERC20(yeti).balanceOf(address(this));
            IStabilityPool(stabilitypool).withdrawFromSP(0);
            uint256 rewards = IERC20(yeti).balanceOf(address(this)) - beforeBalance;
            uint256 afterFee = rewards;
            sendRewards(poolInfo.rewarder, rewards, afterFee);
            emit YetiHarvested(rewards, rewards - afterFee);
        }
        else {
            uint256 beforeBalance = IERC20(yeti).balanceOf(address(this));
            IFarm(poolInfo.addressPool).withdraw(0);
            uint256 rewards = IERC20(yeti).balanceOf(address(this)) - beforeBalance;
            uint256 afterFee = rewards;
            sendRewards(poolInfo.rewarder, rewards, afterFee);
            emit YetiHarvested(rewards, rewards - afterFee);
        }
    }

    function stakeYETI(uint256 amount, address boostedfarm) public {
        if (amount > 0) {
            IERC20(yeti).transferFrom(msg.sender, address(this), amount);
            IERC20(yeti).approve(staking_veyeti, amount);
            IveYETI.RewarderUpdate[] memory arr = new IveYETI.RewarderUpdate[](1);
            arr[0] = IveYETI.RewarderUpdate(boostedfarm, amount , true);
            IveYETI(staking_veyeti).update(arr); 
            /* 
            /// for the mainnet
            uint256 beforeBalance = IERC20(yeti).balanceOf(address(this));
            IRewarderVeYeti(rewarderVeYeti).getReward();
            uint256 rewards = IERC20(yeti).balanceOf(address(this)) - beforeBalance;
            uint256 afterFee = rewards;
            sendRewards(veYETIFee, rewards, afterFee);
            */
            emit NewYetiStaked(amount);
        }
    }

    function stakeAllYETI(address boostedfarm) external {
        stakeYETI(IERC20(yeti).balanceOf(address(this)), boostedfarm);
    }

    function getStakedYeti() external view returns (uint256) {
        return IveYETI(staking_veyeti).getTotalYeti(address(this));
    }

    function getVeYETI() external view returns (uint256) {
        return IveYETI(staking_veyeti).getTotalVeYeti(address(this));
    }


    /// @notice Send rewards to the rewarders
    /// @param rewarder the rewarder that will get the rewards
    /// @param _amount the initial amount of rewards after harvest
    /// @param afterFee the amount to send to the rewarder after fees are collected
    function sendRewards(
        address rewarder,
        uint256 _amount,
        uint256 afterFee
    ) internal {
        uint256 feeInfoLen = feeInfos.length;
        for (uint256 i = 0; i < feeInfoLen; i++) {
            Fees storage feeInfo = feeInfos[i];
            if (feeInfo.isActive) {
                address rewardToken = yeti;
                uint256 feeAmount = (_amount * feeInfo.value) / FEE_DENOMINATOR;
                if (!feeInfo.isYETI) {
                    IERC20(yeti).approve(rgnYETI, feeAmount);
                    IRGNYeti(rgnYETI).deposit(feeAmount);
                    rewardToken = rgnYETI;
                }
                if (!feeInfo.isAddress) {
                    IERC20(rewardToken).approve(feeInfo.to, feeAmount);
                    IBaseRewardPool(feeInfo.to).queueNewRewards(
                        feeAmount,
                        rewardToken
                    );
                } else {
                    ERC20(rewardToken).transfer(feeInfo.to, feeAmount);
                    emit RewardPaidTo(feeInfo.to, rewardToken, feeAmount);
                }
                afterFee -= feeAmount;
            }
        }
        IERC20(yeti).approve(rewarder, afterFee);
        IBaseRewardPool(rewarder).queueNewRewards(afterFee, yeti);
        emit RewardPaidTo(rewarder, yeti, afterFee);
    }

    /// @notice Send Unusual rewards to the rewarders, as airdrops
    /// @dev fees are not collected
    /// @param _token the address of the token to send
    /// @param _rewarder the rewarder that will get the rewards
    function sendTokenRewards(address _token, address _rewarder)
        external
        onlyOwner
    {
        require(_token != yeti, "not authorized");
        require(!pools[_token].isActive, "Not authorized");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).approve(_rewarder, amount);
        IBaseRewardPool(_rewarder).queueNewRewards(amount, _token);
    }

    /// @notice Add a new YETI Pool 
    /// @param _lpAddress The token address for the pool
    /// @param receiptName The name of the fake token
    /// @param receiptSymbol The symbol of the fake token
    /// @param allocPoints RGN allocation reward
    function registerPool(
        address _lpAddress,
        string memory receiptName,
        string memory receiptSymbol,
        uint256 allocPoints, // Number of RGN generated by the pool per second
        bool _stabilitypool,
        address _addressPool
    ) external onlyOwner {
        require(
            pools[_lpAddress].isActive == false,
            "Pool is already registered or active"
        );

        IERC20 newToken = IERC20(
            ERC20FactoryLib.createERC20(receiptName, receiptSymbol)
        );
        address rewarder = IMasterChef(masterChef).createRewarder(
            address(newToken),
            address(yeti)
        );
        IMasterChef(masterChef).add(
            allocPoints,
            address(newToken),
            address(rewarder)
        );
        pools[_lpAddress] = Pool({
            isActive: true,
            lpAddress: _lpAddress,
            sizeLp: 0,
            receiptToken: address(newToken),
            rewarder: address(rewarder),
            stabilitypool: _stabilitypool,
            addressPool : _addressPool
        });
        emit PoolAdded(_lpAddress);
    }

    function getPoolInfo(address _address)
        external
        view
        returns (
            bool isActive,
            address lp,
            uint256 sizeLp,
            address receipt,
            address rewards_addr,
            bool _stabilitypool,
            address addressPool
        )
    {
        Pool storage tokenInfo = pools[_address];
        isActive = tokenInfo.isActive;
        lp = tokenInfo.lpAddress;
        sizeLp = tokenInfo.sizeLp;
        receipt = tokenInfo.receiptToken;
        rewards_addr = tokenInfo.rewarder;
        _stabilitypool = tokenInfo.stabilitypool;
        addressPool = tokenInfo.addressPool;
    }

    function removePool(address token) external onlyOwner {
        pools[token].isActive = false;
    }

    /**
     * @notice Calculate LP tokens for a given amount of receipt tokens
     * @param amount receipt tokens
     * @return deposit tokens
     */
    function getLPTokensForShares(uint256 amount, address token)
        public
        view
        returns (uint256)
    {
        Pool storage poolInfo = pools[token];
        uint256 totalDeposits = poolInfo.sizeLp;
        uint256 totalSupply = IERC20(poolInfo.receiptToken).totalSupply();
        if (totalSupply * totalDeposits == 0) {
            return 0;
        }
        return (amount * totalDeposits) / totalSupply;
    }

    /**
     * @notice Calculate shares amount for a given amount of depositToken
     * @param amount deposit token amount
     * @return number of shares
     */
    function getSharesForDepositTokens(uint256 amount, address token)
        public
        view
        returns (uint256)
    {
        Pool storage poolInfo = pools[token];
        uint256 totalDeposits = poolInfo.sizeLp;
        uint256 totalSupply = IERC20(poolInfo.receiptToken).totalSupply();

        if (totalSupply * totalDeposits == 0) {
            return amount;
        }
        return (amount * totalSupply) / totalDeposits;
    }

    /**
     * @notice Calculate deposit tokens for a given amount of receipt tokens
     * @param amount receipt tokens
     * @return deposit tokens
     */
    function getDepositTokensForShares(uint256 amount, address token)
        public
        view
        returns (uint256)
    {
        Pool storage poolInfo = pools[token];
        uint256 totalDeposits = poolInfo.sizeLp;
        uint256 totalSupply = IERC20(poolInfo.receiptToken).totalSupply();
        if (totalSupply * totalDeposits == 0) {
            return 0;
        }
        return (amount * totalDeposits) / totalSupply;
    }

    // YETI function to manage users data
    function _requireUserHasDeposit(uint256 _initialDeposit) internal pure {
        require(_initialDeposit != 0, "SP: require nonzero deposit");
    }

    function _updateDepositAndSnapshots(address _depositor, uint256 _newValue)
        internal
    {
        deposits[_depositor] = _newValue;

        if (_newValue == 0) {
            address[] memory colls = IYetiController(controller)
                .getValidCollateral();
            uint256 collsLen = colls.length;
            for (uint256 i; i < collsLen; ++i) {
                depositSnapshots[_depositor].S[colls[i]] = 0;
            }
            depositSnapshots[_depositor].P = 0;
            depositSnapshots[_depositor].G = 0;
            depositSnapshots[_depositor].epoch = 0;
            depositSnapshots[_depositor].scale = 0;
            return;
        }

        uint128 currentScaleCached = IStabilityPool(stabilitypool)
            .currentScale();
        uint128 currentEpochCached = IStabilityPool(stabilitypool)
            .currentEpoch();
        uint256 currentP = IStabilityPool(stabilitypool).P();

        address[] memory allColls = IYetiController(controller)
            .getValidCollateral();

        // Get S and G for the current epoch and current scale
        uint256 allCollsLen = allColls.length;
        for (uint256 i; i < allCollsLen; ++i) {
            address token = allColls[i];
            uint256 currentSForToken = IStabilityPool(stabilitypool)
                .epochToScaleToSum(
                    token,
                    currentEpochCached,
                    currentScaleCached
                );
            depositSnapshots[_depositor].S[token] = currentSForToken;
        }

        uint256 currentG = IStabilityPool(stabilitypool).epochToScaleToG(
            currentScaleCached,
            currentEpochCached
        );

        // Record new snapshots of the latest running product P, sum S, and sum G, for the depositor
        depositSnapshots[_depositor].P = currentP;
        depositSnapshots[_depositor].G = currentG;
        depositSnapshots[_depositor].scale = currentScaleCached;
        depositSnapshots[_depositor].epoch = currentEpochCached;
    }

    function getDepositorYETIGain(address _depositor)
        public
        view
        returns (uint256)
    {
        uint256 initialDeposit = deposits[_depositor];
        if (initialDeposit == 0) {
            return 0;
        }
        Snapshots storage snapshots = depositSnapshots[_depositor];

        return _getYETIGainFromSnapshots(initialDeposit, snapshots);
    }

    function _getYETIGainFromSnapshots(
        uint256 initialStake,
        Snapshots storage snapshots
    ) internal view returns (uint256) {
        uint128 epochSnapshot = snapshots.epoch;
        uint128 scaleSnapshot = snapshots.scale;
        uint256 G_Snapshot = snapshots.G;
        uint256 P_Snapshot = snapshots.P;

        uint256 firstPortion = IStabilityPool(stabilitypool)
            .epochToScaleToG(epochSnapshot, scaleSnapshot)
            .sub(G_Snapshot);
        uint256 secondPortion = IStabilityPool(stabilitypool)
            .epochToScaleToG(epochSnapshot, scaleSnapshot.add(1))
            .div(SCALE_FACTOR);

        uint256 YETIGain = initialStake
            .mul(firstPortion.add(secondPortion))
            .div(P_Snapshot)
            .div(DECIMAL_PRECISION);

        return YETIGain;
    }

    function getDepositorGains(address _depositor)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 initialDeposit = deposits[_depositor];

        if (initialDeposit == 0) {
            address[] memory emptyAddress = new address[](0);
            uint256[] memory emptyUint = new uint256[](0);
            return (emptyAddress, emptyUint);
        }

        Snapshots storage snapshots = depositSnapshots[_depositor];

        return _calculateGains(initialDeposit, snapshots);
    }

    function _calculateGains(
        uint256 initialDeposit,
        Snapshots storage snapshots
    )
        internal
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        assets = IYetiController(controller).getValidCollateral();
        uint256 assetsLen = assets.length;
        amounts = new uint256[](assetsLen);
        for (uint256 i; i < assetsLen; ++i) {
            amounts[i] = _getGainFromSnapshots(
                initialDeposit,
                snapshots,
                assets[i]
            );
        }
    }

    function _getGainFromSnapshots(
        uint256 initialDeposit,
        Snapshots storage snapshots,
        address asset
    ) internal view returns (uint256) {
        /*
         * Grab the sum 'S' from the epoch at which the stake was made. The Collateral amount gain may span up to one scale change.
         * If it does, the second portion of the Collateral amount gain is scaled by 1e9.
         * If the gain spans no scale change, the second portion will be 0.
         */
        uint256 S_Snapshot = snapshots.S[asset];
        uint256 P_Snapshot = snapshots.P;

        uint256 firstPortion = IStabilityPool(stabilitypool)
            .epochToScaleToSum(asset, snapshots.epoch, snapshots.scale)
            .sub(S_Snapshot);

        uint256 secondPortion = IStabilityPool(stabilitypool)
            .epochToScaleToSum(asset, snapshots.epoch, snapshots.scale.add(1))
            .div(SCALE_FACTOR);

        uint256 assetGain = initialDeposit
            .mul(firstPortion.add(secondPortion))
            .div(P_Snapshot)
            .div(DECIMAL_PRECISION);

        return assetGain;
    }

    function _sendGainsToDepositor(
        address _to,
        address[] memory assets,
        uint256[] memory amounts
    ) internal {
        uint256 assetsLen = assets.length;
        require(assetsLen == amounts.length, "SP:Length mismatch");
        for (uint256 i; i < assetsLen; ++i) {
            uint256 amount = amounts[i];
            address asset = assets[i];
            if (amount == 0) {
                continue;
            } else {
                IERC20(asset).safeTransfer(_to, amount);
            }
        }
    }

    function getCompoundedYUSDDeposit(address _depositor)
        public
        view
        returns (uint256)
    {
        uint256 initialDeposit = deposits[_depositor];
        if (initialDeposit == 0) {
            return 0;
        }

        Snapshots storage snapshots = depositSnapshots[_depositor];

        uint256 compoundedDeposit = _getCompoundedStakeFromSnapshots(
            initialDeposit,
            snapshots
        );
        return compoundedDeposit;
    }

    function _getCompoundedStakeFromSnapshots(
        uint256 initialStake,
        Snapshots storage snapshots
    ) internal view returns (uint256) {
        uint256 snapshot_P = snapshots.P;
        uint128 scaleSnapshot = snapshots.scale;
        uint128 epochSnapshot = snapshots.epoch;

        // If stake was made before a pool-emptying event, then it has been fully cancelled with debt -- so, return 0
        if (epochSnapshot < IStabilityPool(stabilitypool).currentEpoch()) {
            return 0;
        }

        uint256 compoundedStake;
        uint128 scaleDiff = IStabilityPool(stabilitypool).currentScale().sub(
            scaleSnapshot
        );

        /* Compute the compounded stake. If a scale change in P was made during the stake's lifetime,
         * account for it. If more than one scale change was made, then the stake has decreased by a factor of
         * at least 1e-9 -- so return 0.
         */
        if (scaleDiff == 0) {
            compoundedStake = initialStake
                .mul(IStabilityPool(stabilitypool).P())
                .div(snapshot_P);
        } else if (scaleDiff == 1) {
            compoundedStake = initialStake
                .mul(IStabilityPool(stabilitypool).P())
                .div(snapshot_P)
                .div(SCALE_FACTOR);
        } else {
            // if scaleDiff >= 2
            compoundedStake = 0;
        }

        /*
         * If compounded deposit is less than a billionth of the initial deposit, return 0.
         *
         * NOTE: originally, this line was in place to stop rounding errors making the deposit too large. However, the error
         * corrections should ensure the error in P "favors the Pool", i.e. any given compounded deposit should slightly less
         * than it's theoretical value.
         *
         * Thus it's unclear whether this line is still really needed.
         */
        if (compoundedStake < initialStake.div(1e9)) {
            return 0;
        }

        return compoundedStake;
    }
}
