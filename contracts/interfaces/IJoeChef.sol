// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IJoeChef {
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JOEs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that JOEs distribution occurs.
        uint256 accJoePerShare; // Accumulated JOEs per share, times 1e12. See below.
        address rewarder;
    }
    function poolInfo(uint256 pid) external view returns (PoolInfo memory);
    function totalAllocPoint() external view returns (uint256);
    function pendingTokens(uint256 _pid, address _user) external view
        returns (uint256 pendingJoe, address bonusTokenAddress,
            string memory bonusTokenSymbol, uint256 pendingBonusToken);
    function rewarderBonusTokenInfo(uint256 _pid) external view
        returns (address bonusTokenAddress, string memory bonusTokenSymbol);
    function updatePool(uint256 _pid) external;
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
}