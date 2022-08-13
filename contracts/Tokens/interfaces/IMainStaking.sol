// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMainStaking {


    function setRGNYETI(address _RGNYETI) external;

    function addFee(
        uint256 max,
        uint256 min,
        uint256 value,
        address to,
        bool isYETI,
        bool isAddress
    ) external;

    function setFee(uint256 index, uint256 value) external;

    function setCallerFee(uint256 value) external;

    function deposit(
        address token,
        uint256 amount,
        address sender
    ) external;

    function harvest(address token) external;

    function withdraw(
        address token,
        uint256 _amount,
        address sender
    ) external;

    function stakeYETI(uint256 amount) external;

    function stakeAllYETI() external;

    function claimVeYETI() external;

    function getStakedYETI() external;

    function getVeYETI() external;

    function getLPTokensForShares(uint256 amount, address token)
        external
        view
        returns (uint256);

    function getSharesForDepositTokens(uint256 amount, address token)
        external
        view
        returns (uint256);

    function getDepositTokensForShares(uint256 amount, address token)
        external
        view
        returns (uint256);

    function registerPool(
        uint256 _pid,
        address _lpAddress,
        string memory receiptName,
        string memory receiptSymbol,
        uint256 allocpoints
    ) external;

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
            address contractAddress
        );

    function removePool(address token) external;


}
