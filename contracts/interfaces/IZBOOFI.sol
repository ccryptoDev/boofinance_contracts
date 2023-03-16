// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import "./IERC20WithPermit.sol";

interface IZBOOFI is IERC20WithPermit {
    function enter(uint256 _amount) external;
    function enterFor(address _to, uint256 _amount) external;
    function leave(uint256 _share) external;
    function leaveTo(address _to, uint256 _share) external;
    function currentExchangeRate() external view returns(uint256);
    function expectedZBOOFI(uint256 amountBoofi) external view returns(uint256);
    function expectedBOOFI(uint256 amountZBoofi) external view returns(uint256);
}