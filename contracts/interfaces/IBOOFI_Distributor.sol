// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IBOOFI_Distributor {
    function bips(uint256 arrayIndex) external view returns (uint256);
    function recoverERC20(address token, address to) external;
    function distributeBOOFI() external;
    function checkStakingReward() external view returns (uint256);
}