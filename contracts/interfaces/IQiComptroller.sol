// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IQiComptroller {
    function rewardAccrued(uint8, address) external view returns (uint256);

    function rewardSupplierIndex(uint8, address, address)
        external
        view
        returns (uint256);

    function rewardBorrowerIndex(uint8, address, address)
        external
        view
        returns (uint256);

    function rewardSpeeds(uint8, address) external view returns (uint256);

    function rewardBorrowState(uint8, address) external view returns (uint224, uint32);

    function rewardSupplyState(uint8, address) external view returns (uint224, uint32);

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata CTokens)
        external
        returns (uint256[] memory);

    function exitMarket(address CToken) external returns (uint256);

    /*** Policy Hooks ***/

    function mintAllowed(
        address CToken,
        address minter,
        uint256 mintAmount
    ) external returns (uint256);

    function mintVerify(
        address CToken,
        address minter,
        uint256 mintAmount,
        uint256 mintTokens
    ) external;

    function redeemAllowed(
        address CToken,
        address redeemer,
        uint256 redeemTokens
    ) external returns (uint256);

    function redeemVerify(
        address CToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external;

    function borrowAllowed(
        address CToken,
        address borrower,
        uint256 borrowAmount
    ) external returns (uint256);

    function borrowVerify(
        address CToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayBorrowAllowed(
        address CToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    function repayBorrowVerify(
        address CToken,
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 borrowerIndex
    ) external;

    function liquidateBorrowAllowed(
        address CTokenBorrowed,
        address CTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    function liquidateBorrowVerify(
        address CTokenBorrowed,
        address CTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount,
        uint256 seizeTokens
    ) external;

    function seizeAllowed(
        address CTokenCollateral,
        address CTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256);

    function seizeVerify(
        address CTokenCollateral,
        address CTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    function transferAllowed(
        address CToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external returns (uint256);

    function transferVerify(
        address CToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address CTokenBorrowed,
        address CTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256, uint256);

    //rewardId = 0 for QI, 1 for AVAX
    // Claim all the "COMP" equivalent accrued by holder in all markets
    function claimReward(uint8 rewardId, address holder) external;

    // Claim all the "COMP" equivalent accrued by holder in specific markets
    function claimReward(uint8 rewardId, address holder, address[] calldata CTokens) external;

    // Claim all the "COMP" equivalent accrued by specific holders in specific markets for their supplies and/or borrows
    function claimReward(uint8 rewardId,
        address[] calldata holders,
        address[] calldata CTokens,
        bool borrowers,
        bool suppliers
    ) external;
    

    function markets(address CTokenAddress)
        external
        view
        returns (bool, uint256);
}