// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
/**
 *Submitted for verification at Etherscan.io on 2020-07-17
 */

/*
   ____            __   __        __   _
  / __/__ __ ___  / /_ / /  ___  / /_ (_)__ __
 _\ \ / // // _ \/ __// _ \/ -_)/ __// / \ \ /
/___/ \_, //_//_/\__//_//_/\__/ \__//_/ /_\_\
     /___/
* Synthetix: BaseRewardPool.sol
*
* Docs: https://docs.synthetix.io/
*
*
* MIT License
* ===========
*
* Copyright (c) 2020 Synthetix
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title A contract for managing rewards for a pool
/// @author Ragnar Team
/// @notice You can use this contract for getting informations about rewards for a specific pools
contract BaseRewardPool is Ownable {
    using SafeERC20 for IERC20Metadata;

    address public mainRewardToken;
    address public immutable stakingToken;
    address public immutable operator;

    address[] public rewardTokens;

    uint256 private _totalSupply;

    struct Reward {
        address rewardToken;
        uint256 rewardPerTokenStored;
        uint256 queuedRewards;
        uint256 historicalRewards;
    }

    mapping(address => uint256) private _balances;
    mapping(address => Reward) public rewards;
    mapping(address => mapping(address => uint256))
        public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public userRewards;
    mapping(address => bool) public isRewardToken;
    mapping(address => bool) public poolManagers;
    event RewardAdded(uint256 reward, address indexed token);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(
        address indexed user,
        uint256 reward,
        address indexed token
    );

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _operator,
        address _rewardManager,
        address _mainstaking
    ) {
        stakingToken = _stakingToken;
        operator = _operator;
        rewards[_rewardToken] = Reward({
            rewardToken: _rewardToken,
            rewardPerTokenStored: 0,
            queuedRewards: 0,
            historicalRewards: 0
        });
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;
        poolManagers[_rewardManager] = true;
        poolManagers[_mainstaking] = true;
    }

    /// @notice Returns decimals of reward token
    /// @param _rewardToken Address of reward token
    /// @return Returns decimals of reward token
    function rewardDecimals(address _rewardToken)
        public
        view
        returns (uint256)
    {
        return IERC20Metadata(_rewardToken).decimals();
    }

    /// @notice Returns address of staking token
    /// @return address of staking token
    function getStakingToken() external view returns (address) {
        return stakingToken;
    }

    /// @notice Returns decimals of staking token
    /// @return Returns decimals of staking token
    function stakingDecimals() public view returns (uint256) {
        return IERC20Metadata(stakingToken).decimals();
    }

    /// @notice Returns current supply of staked tokens
    /// @return Returns current supply of staked tokens
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Returns amount of staked tokens by account
    /// @param _account Address account
    /// @return Returns amount of staked tokens by account
    function balanceOf(address _account) external view returns (uint256) {
        return _balances[_account];
    }

    modifier updateReward(address _account) {
        uint256 rewardTokensLength = rewardTokens.length;
        for (uint256 index = 0; index < rewardTokensLength; ++index) {
            address rewardToken = rewardTokens[index];
            userRewards[rewardToken][_account] = earned(_account, rewardToken);
            userRewardPerTokenPaid[rewardToken][_account] = rewardPerToken(
                rewardToken
            );
        }
        _;
    }

    modifier onlyManager() {
        require(poolManagers[msg.sender], "Not a Pool Manager");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "Only Operator");
        _;
    }

    /// @notice Updates the reward information for one account
    /// @param _account Address account
    function updateFor(address _account) external {
        uint256 length = rewardTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address rewardToken = rewardTokens[index];
            userRewards[rewardToken][_account] = earned(_account, rewardToken);
            userRewardPerTokenPaid[rewardToken][_account] = rewardPerToken(
                rewardToken
            );
        }
    }

    /// @notice Returns amount of reward token per staking tokens in pool
    /// @param _rewardToken Address reward token
    /// @return Returns amount of reward token per staking tokens in pool
    function rewardPerToken(address _rewardToken)
        public
        view
        returns (uint256)
    {
        return rewards[_rewardToken].rewardPerTokenStored;
    }

    /// @notice Returns amount of reward token earned by a user
    /// @param _account Address account
    /// @param _rewardToken Address reward token
    /// @return Returns amount of reward token earned by a user
    function earned(address _account, address _rewardToken)
        public
        view
        returns (uint256)
    {
        return (
            (((_balances[_account] *
                (rewardPerToken(_rewardToken) -
                    userRewardPerTokenPaid[_rewardToken][_account])) /
                (10**stakingDecimals())) + userRewards[_rewardToken][_account])
        );
    }

    /// @notice Updates information for a user in case of staking. Can only be called by the Masterchief operator
    /// @param _for Address account
    /// @param _amount Amount of newly staked tokens by the user on masterchief
    /// @return Returns True
    function stakeFor(address _for, uint256 _amount)
        external
        onlyOperator
        updateReward(_for)
        returns (bool)
    {
        _totalSupply = _totalSupply + _amount;
        _balances[_for] = _balances[_for] + _amount;

        emit Staked(_for, _amount);

        return true;
    }

    /// @notice Updates informaiton for a user in case of a withdraw. Can only be called by the Masterchief operator
    /// @param _for Address account
    /// @param _amount Amount of withdrawed tokens by the user on masterchief
    /// @return Returns True
    function withdrawFor(
        address _for,
        uint256 _amount,
        bool claim
    ) external onlyOperator updateReward(_for) returns (bool) {
        _totalSupply = _totalSupply - _amount;
        _balances[_for] = _balances[_for] - _amount;

        emit Withdrawn(_for, _amount);

        if (claim) {
            getReward(_for);
        }

        return true;
    }

    /// @notice Calculates and sends reward to user. Only callable by masterchief
    /// @param _account Address account
    /// @return Returns True
    function getReward(address _account)
        public
        updateReward(_account)
        onlyOperator
        returns (bool)
    {
        uint256 length = rewardTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address rewardToken = rewardTokens[index];
            uint256 reward = earned(_account, rewardToken);
            if (reward > 0) {
                userRewards[rewardToken][_account] = 0;
                IERC20Metadata(rewardToken).safeTransfer(_account, reward);
                emit RewardPaid(_account, reward, rewardToken);
            }
        }
        return true;
    }

    /// @notice Calculates and sends reward to user
    /// @return Returns True
    function getRewardUser() public updateReward(msg.sender) returns (bool) {
        uint256 length = rewardTokens.length;
        for (uint256 index = 0; index < length; ++index) {
            address rewardToken = rewardTokens[index];
            uint256 reward = earned(msg.sender, rewardToken);
            if (reward > 0) {
                userRewards[rewardToken][msg.sender] = 0;
                IERC20Metadata(rewardToken).safeTransfer(msg.sender, reward);
                emit RewardPaid(msg.sender, reward, rewardToken);
            }
        }
        return true;
    }

    /// @notice Sends new rewards to be distributed to the users staking. Only callable by YetiBooster
    /// @param _amountReward Amount of reward token to be distributed
    /// @param _rewardToken Address reward token
    /// @return Returns True
    function queueNewRewards(uint256 _amountReward, address _rewardToken)
        external
        onlyManager
        returns (bool)
    {
        if (!isRewardToken[_rewardToken]) {
            console.log("first if");
            rewardTokens.push(_rewardToken);
            isRewardToken[_rewardToken] = true;
        }
        IERC20Metadata(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amountReward
        );
        Reward storage rewardInfo = rewards[_rewardToken];
        rewardInfo.historicalRewards =
            rewardInfo.historicalRewards +
            _amountReward;
        if (_totalSupply == 0) {
            rewardInfo.queuedRewards += _amountReward;
        } else {
            if (rewardInfo.queuedRewards > 0) {
                _amountReward += rewardInfo.queuedRewards;
                rewardInfo.queuedRewards = 0;
            }
            rewardInfo.rewardPerTokenStored =
                rewardInfo.rewardPerTokenStored +
                (_amountReward * 10**stakingDecimals()) /
                _totalSupply;
        }
        emit RewardAdded(_amountReward, _rewardToken);
        return true;
    }

    /// @notice Sends new rewards to be distributed to the users staking. Only possible to donate already registered token
    /// @param _amountReward Amount of reward token to be distributed
    /// @param _rewardToken Address reward token
    /// @return Returns True
    function donateRewards(uint256 _amountReward, address _rewardToken)
        external
        returns (bool)
    {
        require(isRewardToken[_rewardToken]);
        IERC20Metadata(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amountReward
        );
        Reward storage rewardInfo = rewards[_rewardToken];
        rewardInfo.historicalRewards =
            rewardInfo.historicalRewards +
            _amountReward;
        if (_totalSupply == 0) {
            rewardInfo.queuedRewards += _amountReward;
        } else {
            if (rewardInfo.queuedRewards > 0) {
                _amountReward += rewardInfo.queuedRewards;
                rewardInfo.queuedRewards = 0;
            }
            rewardInfo.rewardPerTokenStored =
                rewardInfo.rewardPerTokenStored +
                (_amountReward * 10**stakingDecimals()) /
                _totalSupply;
        }
        emit RewardAdded(_amountReward, _rewardToken);
        return true;
    }
}
