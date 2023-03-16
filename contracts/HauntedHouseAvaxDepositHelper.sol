// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./interfaces/IHauntedHouse.sol";
import "./interfaces/IWAVAX.sol";

contract HauntedHouseAvaxDepositHelper {

    IHauntedHouse public immutable hauntedHouse;
    IWAVAX public constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 internal constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    modifier onlyEOA {
        require(msg.sender == tx.origin, "HauntedHouseAvaxDepositHelper: onlyEOA");
        _;
    }

    constructor(
        IHauntedHouse _hauntedHouse
        ){
        require(address(_hauntedHouse) != address(0), "zero bad");
        hauntedHouse = _hauntedHouse;
        WAVAX.approve(address(_hauntedHouse), MAX_UINT);
    }

    function deposit() external payable onlyEOA {
        _deposit(msg.sender);
    }

    function depositTo(address to) external payable onlyEOA {
        _deposit(to);
    } 

    function _deposit(address to) internal {
        uint256 amount = msg.value;
        WAVAX.deposit{value: amount}();
        hauntedHouse.deposit(address(WAVAX), amount, to);
    }
}