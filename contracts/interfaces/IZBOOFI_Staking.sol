// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IZBOOFI_Staking {
    function depositTo(address to, uint256 amount) external;
    function depositToWithPermit(address to, uint256 amount, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function NUMBER_TOP_HARVESTERS() external view returns (uint256);
    function topHarvesters(uint256) external view returns (address);
}