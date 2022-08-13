// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewarderVeYeti {
    function updateUserRewards(address _user) external;
    function getReward() external;
}