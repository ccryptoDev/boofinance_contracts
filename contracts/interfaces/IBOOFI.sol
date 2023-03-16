// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import "./IERC20WithPermit.sol";

interface IBOOFI is IERC20WithPermit {
    function mint(address dest, uint256 amount) external;
}