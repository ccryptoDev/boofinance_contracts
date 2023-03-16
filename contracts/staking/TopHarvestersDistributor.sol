// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IZBOOFI_Staking.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TopHarvestersDistributor is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable BOOFI;
    IZBOOFI_Staking public immutable zboofiStaking;
    uint256 public immutable NUMBER_TOP_HARVESTERS;
    uint256 internal constant MAX_BIPS = 10000;
    uint256[] public bips;
    constructor(IERC20 _BOOFI, IZBOOFI_Staking _zboofiStaking, uint256[] memory _bips) {
        //need this local variable as immutable variables are not readable during contract construction
        uint256 amountTopHarvesters = _zboofiStaking.NUMBER_TOP_HARVESTERS();
        NUMBER_TOP_HARVESTERS = amountTopHarvesters;
        require(_bips.length == amountTopHarvesters, "bad bips input");
        uint256 totalBips;
        bips = new uint256[](amountTopHarvesters);
        for (uint256 i = 0; i < amountTopHarvesters; i++) {
            bips[i] = _bips[i];
            totalBips += _bips[i];
        }
        require(totalBips == MAX_BIPS, "wrong bips sum");
        BOOFI = _BOOFI;
        zboofiStaking = _zboofiStaking;
    }
    function claimBOOFI() external {
        uint256 boofiBalance = BOOFI.balanceOf(address(this));
        if (boofiBalance > 0) {
            for (uint256 i = 0; i < NUMBER_TOP_HARVESTERS; i++) {
                BOOFI.safeTransfer(zboofiStaking.topHarvesters(i), (boofiBalance * bips[i]) / MAX_BIPS);
            }            
        }
    }
    function updateParameters(uint256[] memory _bips) external onlyOwner {
        require(_bips.length == NUMBER_TOP_HARVESTERS, "bad bips input");
        uint256 totalBips;
        bips = new uint256[](NUMBER_TOP_HARVESTERS);
        for (uint256 i = 0; i < NUMBER_TOP_HARVESTERS; i++) {
            bips[i] = _bips[i];
            totalBips += _bips[i];
        }
        require(totalBips == MAX_BIPS, "wrong bips sum");
    }
    function recoverERC20(address token, address to) external onlyOwner {
        require(token != address(BOOFI));
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(to, tokenBalance);
    }
}