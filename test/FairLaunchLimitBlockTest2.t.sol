// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {FairLaunchLimitBlockToken} from "../src/FairLaunchLimitBlock.sol";
import {FairLaunchLimitBlockStruct} from "../src/IFairLaunch.sol";

contract FairLaunchLimitBlockTest is Test {
    FairLaunchLimitBlockToken public token;
    FairLaunchLimitBlockToken public tokenWithReserved;

    uint256 public totalIssue = 10000 * 10 ** 18;

    uint256 public reserveTokens = 2000 * 10 ** 18;

    function setUp() public {
        FairLaunchLimitBlockStruct memory params = FairLaunchLimitBlockStruct({
            totalSupply: totalIssue,
            uniswapRouter: address(1),
            uniswapFactory: address(2),
            name: "TestToken",
            symbol: "TT",
            meta: "[]",
            afterBlock: 100,
            softTopCap: 1 ether,
            refundFeeRate: 0,
            refundFeeTo: address(1)
        });

        token = new FairLaunchLimitBlockToken(params);

        FairLaunchLimitBlockStruct
            memory paramsWithReserved = FairLaunchLimitBlockStruct({
                totalSupply: totalIssue,
                uniswapRouter: address(1),
                uniswapFactory: address(2),
                name: "TestToken",
                symbol: "TT",
                meta: "[]",
                afterBlock: 100,
                softTopCap: 1 ether,
                refundFeeRate: 0,
                refundFeeTo: address(1)
            });

        tokenWithReserved = new FairLaunchLimitBlockToken(paramsWithReserved);
    }

    function test_RefundReentrant() public {
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.0002 ether);
        (success, ) = address(token).call{value: 0.0002 ether}("");
        require(success, "refund failed");

        assertEq(0.1002 ether, address(1).balance);
    }

    receive() external payable {
        revert("receive revert");
    }

    fallback() external payable {
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.002 ether);
        (bool success, ) = address(token).call{value: 0.0002 ether}("");
        console.log("fallback refund ");
        console.log(success);
        require(success, "refund failed");
    }
}
