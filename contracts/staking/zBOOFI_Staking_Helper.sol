// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IERC20WithPermit.sol";
import "../interfaces/IZBOOFI.sol";
import "../interfaces/IZBOOFI_Staking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract zBOOFI_Staking_Helper {
    using SafeERC20 for IERC20;

    IERC20WithPermit public immutable BOOFI;
    IZBOOFI public immutable ZBOOFI;
    IZBOOFI_Staking public immutable ZBOOFI_STAKING;
    uint256 internal constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;

    constructor(IERC20WithPermit _BOOFI, IZBOOFI _ZBOOFI, IZBOOFI_Staking _ZBOOFI_STAKING) {
        BOOFI = _BOOFI;
        ZBOOFI = _ZBOOFI;
        ZBOOFI_STAKING = _ZBOOFI_STAKING;
        _BOOFI.approve(address(_ZBOOFI), MAX_UINT);
        _ZBOOFI.approve(address(_ZBOOFI_STAKING), MAX_UINT);
    }

    //turn 'amountBoofi' BOOFI tokens into zBOOFI tokens for the caller
    function deposit(uint256 amountBoofi) public {
        IERC20(address(BOOFI)).safeTransferFrom(msg.sender, address(this), amountBoofi);
        ZBOOFI.enterFor(msg.sender, amountBoofi);
    }

    //same as deposit, but with a permit call first
    function depositWithPermit(uint256 amountBoofi, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        BOOFI.permit(msg.sender, address(this), value, deadline, v, r, s);
        deposit(amountBoofi);
    }

    //turn 'amountBoofi' BOOFI tokens into zBOOFI tokens, then stake those zBOOFI tokens
    function depositAndStake(uint256 amountBoofi) public {
        IERC20(address(BOOFI)).safeTransferFrom(msg.sender, address(this), amountBoofi);
        ZBOOFI.enter(amountBoofi);
        uint256 zboofiBal = ZBOOFI.balanceOf(address(this));
        ZBOOFI_STAKING.depositTo(msg.sender, zboofiBal);
    }

    //same as depositAndStake, but with a permit call first
    function depositAndStakeWithPermit(uint256 amountBoofi, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        BOOFI.permit(msg.sender, address(this), value, deadline, v, r, s);
        depositAndStake(amountBoofi);
    }
}