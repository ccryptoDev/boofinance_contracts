// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ERC20WithVotingAndPermit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BOOFI is ERC20WithVotingAndPermit("Boo Finance Token", "BOOFI"), Ownable {
    uint256 public constant YEAR_ONE_CAP = 10e24; //10 million tokens
    uint256 public immutable END_OF_YEAR_ONE;
    constructor() {
        END_OF_YEAR_ONE = block.timestamp + 365 days;
    }
    function mint(address account, uint256 amount) external onlyOwner {
        if(block.timestamp < END_OF_YEAR_ONE) {
            require((totalSupply() + amount) <= YEAR_ONE_CAP, "mint would exceed cap");
        }
        _mint(account, amount);
    }
}