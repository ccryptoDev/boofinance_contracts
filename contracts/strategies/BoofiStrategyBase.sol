// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../interfaces/IBoofiStrategy.sol";
import "../interfaces/IHauntedHouse.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoofiStrategyBase is IBoofiStrategy, Ownable {
    using SafeERC20 for IERC20;

    IHauntedHouse public immutable hauntedHouse;
    IERC20 public immutable depositToken;
    uint256 public performanceFeeBips = 3000;
    uint256 internal constant MAX_UINT = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 internal constant ACC_BOOFI_PRECISION = 1e18;
    uint256 internal constant MAX_BIPS = 10000;

    constructor(
        IHauntedHouse _hauntedHouse,
        IERC20 _depositToken
        ){
        require(address(_hauntedHouse) != address(0) && address(_depositToken) != address(0),"zero bad");
        hauntedHouse = _hauntedHouse;
        depositToken = _depositToken;
        transferOwnership(address(_hauntedHouse));
    }

    function pendingTokens(address) external view virtual override returns(address[] memory, uint256[] memory) {
        address[] memory tokens = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        return (tokens, amounts);
    }

    function deposit(address, address, uint256, uint256) external virtual override onlyOwner {
    }

    function withdraw(address, address to, uint256 tokenAmount, uint256) external virtual override onlyOwner {
        if (tokenAmount > 0) {
            depositToken.safeTransfer(to, tokenAmount);
        }
    }

    function inCaseTokensGetStuck(IERC20 token, address to, uint256 amount) external virtual override onlyOwner {
        require(amount > 0, "cannot recover 0 tokens");
        require(address(token) != address(depositToken), "cannot recover deposit token");
        token.safeTransfer(to, amount);
    }

    function migrate(address newStrategy) external virtual override onlyOwner {
        uint256 toTransfer = depositToken.balanceOf(address(this));
        depositToken.safeTransfer(newStrategy, toTransfer);
    }

    function onMigration() external virtual override onlyOwner {
    }

    function transferOwnership(address newOwner) public virtual override(Ownable, IBoofiStrategy) onlyOwner {
        Ownable.transferOwnership(newOwner);
    }

    function setPerformanceFeeBips(uint256 newPerformanceFeeBips) external virtual onlyOwner {
        require(newPerformanceFeeBips <= MAX_BIPS, "input too high");
        performanceFeeBips = newPerformanceFeeBips;
    }
}