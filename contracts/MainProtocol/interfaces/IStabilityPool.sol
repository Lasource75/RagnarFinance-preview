// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStabilityPool {

        
    function provideToSP(uint256 _amount) external;
    function withdrawFromSP(uint256 _amount) external;
    function P() external view returns(uint256);
    function currentScale() external view returns(uint128);
    function currentEpoch() external view returns(uint128);
    function epochToScaleToG(uint128 scale, uint128 epoch) external view returns(uint256);
    function epochToScaleToSum(address token, uint128 scale, uint128 sum) external view returns(uint256);
}