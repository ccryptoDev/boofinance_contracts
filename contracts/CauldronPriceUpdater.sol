// SPDX-License-Identifier: MIT
//based on: https://github.com/Uniswap/uniswap-v2-periphery/tree/master/contracts/examples
pragma solidity ^0.8.6;

import "./interfaces/IHauntedHouse.sol";
import "./interfaces/IUniswapV2TWAP.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CauldronPriceUpdater is Ownable {
    address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    //whitelist of addresses that can call this contract
    mapping(address => bool) public whitelist;
    //tracks whether a token is an LP or not
    mapping(address => bool) public lpTokens;
    //tracks whether a token is a staked token like xSUSHI or not
    mapping(address => bool) public stakedTokens;
    //underlying tokens of staked tokens
    mapping(address => address) public underlyingTokenOfStakedTokens;
    //address of oracle to consult
    address public oracle;
    //address of HauntedHouse
    address public immutable hauntedHouse;
    event OracleSet();
    modifier onlyWhitelist() {
        require(whitelist[msg.sender], "only callable by whitelisted addresses");
        _;
    }
    constructor(address _hauntedHouse, address _oracle) {
        hauntedHouse = _hauntedHouse;
        setOracle(_oracle);
        whitelist[msg.sender] = true;
    }
    //VIEW FUNCTIONS
    function getTokenPriceView(address token) public view returns (uint256) {
        //NOTE: return value is SCALED UP by 1e18, as this is the input amount in consulting the oracle
        if (token != WAVAX) {
            return IUniswapV2TWAP(oracle).consult(token, WAVAX, token, 1e18);
        } else {
            return 1e18;
        }
    }
    function getPriceOfLPView(address lpToken) public view returns (uint256) {
        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();
        uint256 priceToken0 = getTokenPriceView(token0);
        uint256 priceToken1 = getTokenPriceView(token1);
        (uint256 balanceToken0, uint256 balanceToken1, ) = IUniswapV2Pair(lpToken).getReserves();
        uint256 lpTVL = (priceToken0 * balanceToken0) + (priceToken1 * balanceToken1);
        return lpTVL / IUniswapV2Pair(lpToken).totalSupply();
    }
    function getPriceOfStakedTokenView(address stakedToken) public view returns (uint256) {
        address underlyingToken = underlyingTokenOfStakedTokens[stakedToken];
        uint256 underlyingTokenBalance = IERC20(underlyingToken).balanceOf(stakedToken);
        uint256 totalSupplyOfStakedToken = IERC20(stakedToken).totalSupply();
        if (totalSupplyOfStakedToken != 0) {
            uint256 underlyingTokenPrice = getTokenPriceView(underlyingToken);
            return (underlyingTokenPrice * underlyingTokenBalance) / totalSupplyOfStakedToken;
        } else {
            return 0;
        }
    }
    //PUBLIC WRITE FUNCTIONS
    function getTokenPrice(address token) public returns (uint256) {
        //NOTE: return value is SCALED UP by 1e18, as this is the input amount in consulting the oracle
        if (token != WAVAX) {
            return IUniswapV2TWAP(oracle).consultWithUpdate(token, WAVAX, token, 1e18);
        } else {
            return 1e18;
        }
    }
    function getPriceOfLP(address lpToken) public returns (uint256) {
        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();
        uint256 priceToken0 = getTokenPrice(token0);
        uint256 priceToken1 = getTokenPrice(token1);
        (uint256 balanceToken0, uint256 balanceToken1, ) = IUniswapV2Pair(lpToken).getReserves();
        uint256 lpTVL = (priceToken0 * balanceToken0) + (priceToken1 * balanceToken1);
        return lpTVL / IUniswapV2Pair(lpToken).totalSupply();
    }
    function getPriceOfStakedToken(address stakedToken) public returns (uint256) {
        address underlyingToken = underlyingTokenOfStakedTokens[stakedToken];
        uint256 underlyingTokenBalance = IERC20(underlyingToken).balanceOf(stakedToken);
        uint256 totalSupplyOfStakedToken = IERC20(stakedToken).totalSupply();
        if (totalSupplyOfStakedToken != 0) {
            uint256 underlyingTokenPrice = getTokenPrice(underlyingToken);
            return (underlyingTokenPrice * underlyingTokenBalance) / totalSupplyOfStakedToken;
        } else {
            return 0;
        }
    }
    //OWNER-ONLY FUNCTIONS
    function setOracle(address _oracle) public onlyOwner {
        oracle = _oracle;
    }
    function modifyWhitelist(address[] calldata addresses, bool[] calldata statuses) external onlyOwner {
        require(addresses.length == statuses.length, "input length mismatch");
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = statuses[i];
        }
    }
    function addLPTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(IUniswapV2Pair(tokens[i]).factory() != address(0), "not an LP token");
            lpTokens[tokens[i]] = true;
        }
    }
    function removeLPTokens(address[] calldata tokens) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            lpTokens[tokens[i]] = false;
        }
    }
    function addStakedToken(address _stakedToken, address _underlyingToken) external onlyOwner {
        stakedTokens[_stakedToken] = true;
        underlyingTokenOfStakedTokens[_stakedToken] = _underlyingToken;
    }
    function removeStakedToken(address _stakedToken) external onlyOwner {
        stakedTokens[_stakedToken] = false;
        underlyingTokenOfStakedTokens[_stakedToken] = address(0);
    }
    //WHITELIST-ONLY FUNCTIONS
    function setPrice(address token) public onlyWhitelist {
        uint256 tokenPrice;
        if(lpTokens[token]) {
            tokenPrice = getPriceOfLP(token);
        } else if(stakedTokens[token]) {
            tokenPrice = getPriceOfStakedToken(token);
        } else {
            tokenPrice = getTokenPrice(token);
        }
        IHauntedHouse(hauntedHouse).updatePrice(token, tokenPrice);
    }
    function setPrices(address[] memory tokens) public onlyWhitelist {
        uint256[] memory tokenPrices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if(lpTokens[tokens[i]]) {
                tokenPrices[i] = getPriceOfLP(tokens[i]);
            } else if (stakedTokens[tokens[i]]) {
                tokenPrices[i] = getPriceOfStakedToken(tokens[i]);
            } else {
                tokenPrices[i] = getTokenPrice(tokens[i]);
            }
        }
        IHauntedHouse(hauntedHouse).updatePrices(tokens, tokenPrices);
    }
    function setAllPrices() external onlyWhitelist {
        address[] memory tokens = IHauntedHouse(hauntedHouse).tokenList();
        setPrices(tokens);
    }
}