// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IOracle {
    function getPrice(address token) external returns (uint256);
}