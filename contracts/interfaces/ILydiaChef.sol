// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ILydiaChef {
    function lyd() external view returns (address);
    function electrum() external view returns (address);
    function lydPerSec() external view returns (uint256);
    function pendingLyd(uint256 _pid, address _user) external view returns (uint256);
    function poolInfo(uint256 pid) external view returns (
        address lpToken,
        uint256 allocPoint,
        uint256 lastRewardTimestamp,
        uint256 accLydPerShare
    );
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
}