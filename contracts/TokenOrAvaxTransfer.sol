// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TokenOrAvaxTransfer {
    using SafeERC20 for IERC20;

    //placeholder address for native token (AVAX)
    address public constant AVAX = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function _tokenOrAvaxTransfer(address token, address dest, uint256 amount) internal {
        if (amount > 0) {
            if (token == AVAX) {
                payable(dest).transfer(amount);
            } else {
                IERC20(token).safeTransfer(dest,amount);          
            }            
        }
    }

    function _checkBalance(address token) internal view returns (uint256) {
        if (token == AVAX) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }
}