// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IJoeComptroller {
    function rewardDistributor() external view returns (address);
}