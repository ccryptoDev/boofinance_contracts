// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IUniswapV2TWAP {
    function consult(address tokenA, address tokenB, address tokenIn, uint256 amountIn) external view returns (uint256 amountOut);
    function consultWithUpdate(address tokenA, address tokenB, address tokenIn, uint256 amountIn) external returns (uint256 amountOut);
}