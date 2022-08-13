// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IveYETI {
    
    struct RewarderUpdate {
        address rewarder;
        uint256 amount;
        bool isIncrease;
    }
    
    function update(RewarderUpdate[] memory _yetiAdjustments) external;

    function getTotalVeYeti(address _user) external view returns (uint256);

    function getTotalYeti(address _user) external view returns (uint256);

}
