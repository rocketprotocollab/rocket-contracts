// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFairLaunch {
    event Deployed(address indexed addr, uint256 _type);
    event FundEvent(
        address indexed to,
        uint256 ethAmount,
        uint256 amountOfTokens
    );

    event LaunchEvent(
        address indexed to,
        uint256 amount,
        uint256 ethAmount,
        uint256 liquidity
    );
    event RefundEvent(address indexed from, uint256 amount, uint256 eth);
}

struct FairLaunchLimitAmountStruct {
    uint256 price;
    uint256 amountPerUnits;
    uint256 totalSupply;
    address launcher;
    address uniswapRouter;
    address uniswapFactory;
    string name;
    string symbol;
    string meta;
    uint256 eachAddressLimitEthers;
    uint256 refundFeeRate;
    address refundFeeTo;
}

struct FairLaunchLimitBlockStruct {
    uint256 totalSupply;
    address uniswapRouter;
    address uniswapFactory;
    string name;
    string symbol;
    string meta;
    uint256 afterBlock;
    uint256 softTopCap;
    uint256 refundFeeRate;
    address refundFeeTo;
}
