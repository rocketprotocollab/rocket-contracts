// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {FairLaunchLimitBlockToken, IUniswapV2Router02, IUniswapV2Factory} from "../src/FairLaunchLimitBlock.sol";

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IFairLaunch, FairLaunchLimitBlockStruct} from "../src/IFairLaunch.sol";

contract LP is ERC20 {
    constructor() ERC20("LP", "LP") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // transfer
    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _update(msg.sender, to, amount);
        return true;
    }
}

contract UniswapFactoryMock is IUniswapV2Factory {
    LP public lp;

    constructor() {
        lp = new LP();
    }

    function getPair(
        address tokenA,
        address tokenB
    ) external view override returns (address pair) {
        return address(lp);
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external override returns (address pair) {
        return address(lp);
    }
}

contract UniswapRouterMock is IUniswapV2Router02 {
    IUniswapV2Factory public factory;

    constructor(IUniswapV2Factory _factory) {
        factory = _factory;
    }

    function WETH() external pure override returns (address) {
        return address(1);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        override
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        // transfer token to message sender
        LP lpToken = LP(factory.getPair(token, address(1)));
        lpToken.mint(msg.sender, 10000 * 10 ** 18);
        return (0, 0, 0);
    }
}

contract FairLaunchLimitBlockTest is Test {
    FairLaunchLimitBlockToken public token;
    FairLaunchLimitBlockToken public tokenExpired;

    IUniswapV2Factory public factory;
    IUniswapV2Router02 public router;

    uint256 public totalIssue = 10000 * 10 ** 18;

    function setUp() public {
        factory = new UniswapFactoryMock();
        router = new UniswapRouterMock(factory);

        FairLaunchLimitBlockStruct memory params1 = FairLaunchLimitBlockStruct(
            totalIssue,
            address(router),
            address(factory),
            "TestToken",
            "TT",
            "[]",
            100, // after 100 blocks
            1 ether,
            600, // 6%
            address(10)

        );

        token = new FairLaunchLimitBlockToken(params1);

        FairLaunchLimitBlockStruct memory params2 = FairLaunchLimitBlockStruct(
            totalIssue,
            address(router),
            address(factory),
            "TestToken",
            "TT",
            "[]",
            0, // after 0 blocks
            1 ether,
            0,
            address(1)
        );

        tokenExpired = new FairLaunchLimitBlockToken(params2);
    }

    // test over soft top cap
    function testFail_overSoftTopCap() public {
        //
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        vm.prank(address(2), address(2));
        vm.deal(address(2), 1 ether);
        (bool success1, ) = address(token).call{value: 1 ether}("");
        vm.expectRevert("FairMint: soft top cap reached");
        require(success1, "transfer failed");
    }

    function test_fundNoReserve() public {
        // transfer 0.1 ether to the contract address
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        vm.prank(address(2), address(2));
        vm.deal(address(2), 0.2 ether);
        (bool success1, ) = address(token).call{value: 0.2 ether}("");
        require(success1, "transfer failed");

        vm.prank(address(3), address(3));
        vm.deal(address(3), 0.3 ether);
        (bool success2, ) = address(token).call{value: 0.3 ether}("");
        require(success2, "transfer failed");

        vm.prank(address(4), address(4));
        vm.deal(address(4), 0.4 ether);
        (bool success3, ) = address(token).call{value: 0.4 ether}("");
        require(success3, "transfer failed");

        // might get
        uint256 mightGet1 = token.mightGet(address(1));
        uint256 mightGet2 = token.mightGet(address(2));
        uint256 mightGet3 = token.mightGet(address(3));
        uint256 mightGet4 = token.mightGet(address(4));

        assertEq(mightGet1, totalIssue / 2 / 10); // 1/10
        assertEq(mightGet2, (totalIssue / 2 / 10) * 2); // 2/10
        assertEq(mightGet3, (totalIssue / 2 / 10) * 3); //  3/10
        assertEq(mightGet4, (totalIssue / 2 / 10) * 4); // 4/10
    }

    function test_fundAfterRefund() public {
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        vm.prank(address(2), address(2));
        vm.deal(address(2), 0.2 ether);
        (bool success1, ) = address(token).call{value: 0.2 ether}("");
        require(success1, "transfer failed");

        vm.prank(address(3), address(3));
        vm.deal(address(3), 0.3 ether);
        (bool success2, ) = address(token).call{value: 0.3 ether}("");
        require(success2, "transfer failed");

        vm.prank(address(4), address(4));
        vm.deal(address(4), 0.4 ether);
        (bool success3, ) = address(token).call{value: 0.4 ether}("");
        require(success3, "transfer failed");

        // refund and fund again
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.0002 ether);
        (bool successRefund1, ) = address(token).call{value: 0.0002 ether}("");
        require(successRefund1, "transfer failed");
        assertEq(address(1).balance, 0.1 ether * 94 / 100 + 0.0002 ether);
        assertEq(token.mightGet(address(1)), 0);

        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (success, ) = address(token).call{value: 0.1 ether}("");

        // might get
        uint256 mightGet1 = token.mightGet(address(1));
        uint256 mightGet2 = token.mightGet(address(2));
        uint256 mightGet3 = token.mightGet(address(3));
        uint256 mightGet4 = token.mightGet(address(4));

        assertEq(mightGet1, totalIssue / 2 / 10); // 1/10
        assertEq(mightGet2, (totalIssue / 2 / 10) * 2); // 2/10
        assertEq(mightGet3, (totalIssue / 2 / 10) * 3); //  3/10
        assertEq(mightGet4, (totalIssue / 2 / 10) * 4); // 4/10
    }

    // after expire block, you can not fund
    function testFail_fundAfterExpireBlock() public {
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(tokenExpired).call{value: 0.1 ether}("");
        vm.expectRevert("FairMint: invalid command - start or refund only");
        require(success, "transfer failed");
    }

    // fund after start - should fail
    function testFail_fundAfterStart() public {
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(token).call{value: 0.05 ether}("");
        require(success, "transfer failed");

        vm.prank(address(2), address(2));
        vm.deal(address(2), 0.2 ether);
        (bool success1, ) = address(token).call{value: 0.2 ether}("");
        require(success1, "transfer failed");

        vm.prank(address(3), address(3));
        vm.deal(address(3), 0.3 ether);
        (bool success2, ) = address(token).call{value: 0.3 ether}("");
        require(success2, "transfer failed");

        vm.prank(address(4), address(4));
        vm.deal(address(4), 0.4 ether);
        (bool success3, ) = address(token).call{value: 0.4 ether}("");
        require(success3, "transfer failed");

        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (success, ) = address(token).call{value: 0.05 ether}("");
        require(success, "transfer failed");

        // set block
        vm.roll(block.number + 101);
        // send start command
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.0005 ether);

        // check drop lp event
        // vm.expectEmit(true, true, true, true);
        // emit IERC20.Transfer(address(token), address(0), 10000 * 10 ** 18);
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        bool started = token.started();
        assertEq(started, true);

        // fund after start - should fail
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (success, ) = address(token).call{value: 0.1 ether}("");

        vm.expectRevert("FairMint: invalid command - mint only");
        require(success, "transfer failed");
    }

    // drop lp after start
    function test_DropLp() public {
        // transfer 0.1 ether to the contract address
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        vm.prank(address(2), address(2));
        vm.deal(address(2), 0.2 ether);
        (bool success1, ) = address(token).call{value: 0.2 ether}("");
        require(success1, "transfer failed");

        vm.prank(address(3), address(3));
        vm.deal(address(3), 0.3 ether);
        (bool success2, ) = address(token).call{value: 0.3 ether}("");
        require(success2, "transfer failed");

        vm.prank(address(4), address(4));
        vm.deal(address(4), 0.4 ether);
        (bool success3, ) = address(token).call{value: 0.4 ether}("");
        require(success3, "transfer failed");

        // set block
        vm.roll(block.number + 101);
        // send start command
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.0005 ether);

        // check drop lp event
        // vm.expectEmit(true, true, true, false);
        // emit IERC20.Transfer(address(token), address(0), 10000 * 10 ** 18);

        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");
        bool started = token.started();
        assertEq(started, true);

        // check lp balance
        LP lp = LP(factory.getPair(address(token), address(1)));
        assertEq(lp.balanceOf(address(token)), 0);
    }

    // function testFail_fundAfterMint() public {

    // }

    // // test refund
    function test_refund() public {
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.1002 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        uint256 mightGet = token.mightGet(address(1));
        console.log("mightGet: ", mightGet);
        assertEq(mightGet, totalIssue / 2); // all tokens
        assertEq(address(1).balance, 0.0002 ether);
        // refund
        (bool successRefund, ) = address(token).call{value: 0.0002 ether}("");
        require(successRefund, "transfer failed");

        uint256 mightGet2 = token.mightGet(address(1));
        assertEq(mightGet2, 0); // zero tokens

        console.log("address(1).balance: ", address(1).balance);
        // address(10)
        console.log("address(10).balance: ", address(10).balance);
        assertEq(address(1).balance, 0.1000 ether * 94 / 100 + 0.0002 ether);
        assertEq(address(10).balance, 0.100 ether * 6 / 100);
        vm.stopPrank();
    }

    // // test refund after refund
    function testFail_refundAfterRefund() public {
        // refund()
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.1002 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        uint256 mightGet = token.mightGet(address(1));
        assertEq(mightGet, totalIssue / 2); // all tokens
        assertEq(address(1).balance, 0.0002 ether);
        // refund
        (bool successRefund, ) = address(token).call{value: 0.0002 ether}("");
        require(successRefund, "transfer failed");

        uint256 mightGet2 = token.mightGet(address(1));
        assertEq(mightGet2, 0); // zero tokens

        // balance of address(1)
        assertEq(address(1).balance, 0.1002 ether);

        // refund again
        (bool successRefund2, ) = address(token).call{value: 0.0002 ether}("");
        vm.expectRevert("FairMint: no fund");
        require(successRefund2, "transfer failed");
        vm.stopPrank();
    }

    // // test refund after expire block
    function test_refundAfterExpireBlockAndBeforeStart() public {
        // refund()
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.1002 ether);

        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        uint256 mightGet = token.mightGet(address(1));
        assertEq(mightGet, totalIssue / 2); // all tokens

        // set block
        vm.roll(block.number + 101);

        // refund
        (bool successRefund, ) = address(token).call{value: 0.0002 ether}("");
        require(successRefund, "transfer failed");

        uint256 mightGet2 = token.mightGet(address(1));
        assertEq(mightGet2, 0); // zero tokens

        // balance of address(1)
        assertEq(address(1).balance, 0.1 ether * 94 / 100 + 0.0002 ether);
        vm.stopPrank();
    }

    // testFail refund after start
    function testFail_refundAfterStart() public {
        // refund()
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.1007 ether);

        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        uint256 mightGet = token.mightGet(address(1));
        assertEq(mightGet, totalIssue / 2); // all tokens

        // set block
        vm.roll(block.number + 101);

        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        // refund
        (bool successRefund, ) = address(token).call{value: 0.0002 ether}("");
        vm.expectRevert("FairMint: invalid command - mint only");
        require(successRefund, "transfer failed");
    }

    // // testFail refund after mint
    // function testFail_refundAfterMint() public {
    //     // refund()
    // }

    function test_start() public {
        // start()
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.1005 ether);

        // fund
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        // set block
        vm.roll(block.number + 101);

        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        bool started = token.started();
        assertEq(started, true);
        vm.stopPrank();
    }

    function testFail_startAgain() public {
        // start()
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.2005 ether);

        // fund
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        // set block
        vm.roll(block.number + 101);

        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        bool started = token.started();
        assertEq(started, true);

        // start again
        (success, ) = address(token).call{value: 0.0005 ether}("");
        vm.expectRevert("FairMint: already started");
        require(success, "transfer failed");

        vm.stopPrank();
    }

    function testFaill_startBeforeExpireBlock() public {
        // start()
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.1005 ether);

        // fund
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        // set block
        // vm.roll(block.number + 101);

        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        bool started = token.started();
        assertEq(started, true);
        vm.stopPrank();
    }

    function test_mint() public {
        // mint(uint256 _amount)
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.2 ether);

        // fund
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");

        // set block
        vm.roll(block.number + 101);

        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        // started
        bool started = token.started();
        assertEq(started, true);

        // mint
        (success, ) = address(token).call{value: 0.0001 ether}("");
        require(success, "transfer failed");

        // check minted
        assertEq(token.balanceOf(address(1)), totalIssue / 2);
    }

    // test multiple address mint
    function test_mintMultipleAddress() public {
        // mint(uint256 _amount)
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.2 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");
        vm.stopPrank();

        // fund
        vm.startPrank(address(2), address(2));
        vm.deal(address(2), 0.2 ether);
        (bool success1, ) = address(token).call{value: 0.2 ether}("");
        require(success1, "transfer failed");
        vm.stopPrank();

        // fund
        vm.startPrank(address(3), address(3));
        vm.deal(address(3), 0.3 ether);
        (bool success2, ) = address(token).call{value: 0.3 ether}("");
        require(success2, "transfer failed");
        vm.stopPrank();

        vm.startPrank(address(4), address(4));
        vm.deal(address(4), 0.4 ether);
        // fund
        (bool success3, ) = address(token).call{value: 0.4 ether}("");
        require(success3, "transfer failed");
        vm.stopPrank();

        // set block
        vm.roll(block.number + 101);

        vm.startPrank(address(1), address(1));
        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        // started
        bool started = token.started();
        assertEq(started, true);
        vm.stopPrank();

        // mint
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.0001 ether);
        (success, ) = address(token).call{value: 0.0001 ether}("");
        require(success, "transfer failed");

        vm.prank(address(2), address(2));
        vm.deal(address(2), 0.0001 ether);
        (success1, ) = address(token).call{value: 0.0001 ether}("");
        require(success1, "transfer failed");

        vm.prank(address(3), address(3));
        vm.deal(address(3), 0.0001 ether);
        (success2, ) = address(token).call{value: 0.0001 ether}("");
        require(success2, "transfer failed");

        vm.prank(address(4), address(4));
        vm.deal(address(4), 0.0001 ether);
        (success3, ) = address(token).call{value: 0.0001 ether}("");
        require(success3, "transfer failed");

        // check minted
        assertEq(token.balanceOf(address(1)), totalIssue / 2 / 10);
        assertEq(token.balanceOf(address(2)), (totalIssue / 2 / 10) * 2);
        assertEq(token.balanceOf(address(3)), (totalIssue / 2 / 10) * 3);
        assertEq(token.balanceOf(address(4)), (totalIssue / 2 / 10) * 4);
    }

    // // testFail mint before start
    // function testFail_mintBeforeStart() public {
    //     // mint(uint256 _amount)
    // }

    // testFail_mintAfterMinted
    function testFail_mintAfterMinted() public {
        // mint(uint256 _amount)
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.2 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");
        vm.stopPrank();

        vm.startPrank(address(2), address(2));
        vm.deal(address(2), 0.2 ether);
        (bool success1, ) = address(token).call{value: 0.2 ether}("");
        require(success1, "transfer failed");
        vm.stopPrank();

        vm.startPrank(address(3), address(3));
        vm.deal(address(3), 0.3 ether);
        (bool success2, ) = address(token).call{value: 0.3 ether}("");
        require(success2, "transfer failed");
        vm.stopPrank();

        vm.startPrank(address(4), address(4));
        vm.deal(address(4), 0.4 ether);
        (bool success3, ) = address(token).call{value: 0.4 ether}("");
        require(success3, "transfer failed");
        vm.stopPrank();

        // set block
        vm.roll(block.number + 101);

        vm.startPrank(address(1), address(1));
        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");

        // started
        bool started = token.started();
        assertEq(started, true);
        vm.stopPrank();

        // mint
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.0001 ether);
        (success, ) = address(token).call{value: 0.0001 ether}("");
        require(success, "transfer failed");

        // check minted
        assertEq(token.balanceOf(address(1)), totalIssue / 2 / 10);

        // mint again
        vm.prank(address(1), address(1));
        vm.deal(address(1), 0.0001 ether);
        (success, ) = address(token).call{value: 0.0001 ether}("");
        vm.expectRevert("FairMint: already minted");
    }

    function test_OverSoftTopCapAndClaimExtra() public {
        // fund
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.1 ether);
        (bool success, ) = address(token).call{value: 0.1 ether}("");
        require(success, "transfer failed");
        vm.stopPrank();

        vm.startPrank(address(2), address(2));
        vm.deal(address(2), 1 ether);
        (bool success1, ) = address(token).call{value: 0.2 ether}("");
        require(success1, "transfer failed");
        vm.stopPrank();

        vm.startPrank(address(3), address(3));
        vm.deal(address(3), 1 ether);
        (bool success2, ) = address(token).call{value: 0.3 ether}("");
        require(success2, "transfer failed");
        vm.stopPrank();

        vm.startPrank(address(4), address(4));
        vm.deal(address(4), 1 ether);
        (bool success3, ) = address(token).call{value: 0.4 ether}("");
        require(success3, "transfer failed");
        vm.stopPrank();

        // 5
        vm.startPrank(address(5), address(5));
        vm.deal(address(5), 1 ether);
        (bool success4, ) = address(token).call{value: 0.5 ether}("");
        require(success4, "transfer failed");
        vm.stopPrank();

        // 6
        vm.startPrank(address(6), address(6));
        vm.deal(address(6), 1 ether);
        (bool success5, ) = address(token).call{value: 0.6 ether}("");
        require(success5, "transfer failed");
        vm.stopPrank();

        // set block
        vm.roll(block.number + 101);

        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.0005 ether);
        // start
        (success, ) = address(token).call{value: 0.0005 ether}("");
        require(success, "transfer failed");
        vm.stopPrank();

        // started
        bool started = token.started();
        assertEq(started, true);

        // total ethers
        uint256 totalEthers = 0.1 ether +
            0.2 ether +
            0.3 ether +
            0.4 ether +
            0.5 ether +
            0.6 ether;
        uint256 extraEthers = totalEthers - 1 ether;

        // 10000 tokens total supply
        uint256 totalTokens = totalIssue / 2;
        // address 1 mint
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.0001 ether);
        (success, ) = address(token).call{value: 0.0001 ether}("");
        require(success, "transfer failed");
        assertEq(token.mightGet(address(1)), token.balanceOf(address(1)));
        console.log("total tokens: ", token.balanceOf(address(1)));
        uint256 myFundEth = token.fundBalanceOf(address(1));
        console.log("my fund eth: ", myFundEth);
        uint256 mySupposedTokens = (totalTokens * myFundEth) / totalEthers;
        console.log("my supposed tokens: ", mySupposedTokens);
        assertEq(token.balanceOf(address(1)), mySupposedTokens);
        vm.stopPrank();

        // address 2 mint
        vm.startPrank(address(2), address(2));
        vm.deal(address(2), 0.0001 ether);
        (success, ) = address(token).call{value: 0.0001 ether}("");
        require(success, "transfer failed");
        assertEq(token.mightGet(address(2)), token.balanceOf(address(2)));
        console.log("total tokens: ", token.balanceOf(address(2)));
        myFundEth = token.fundBalanceOf(address(2));
        console.log("my fund eth: ", myFundEth);
        mySupposedTokens = (totalTokens * myFundEth) / totalEthers;
        console.log("my supposed tokens: ", mySupposedTokens);
        assertEq(token.balanceOf(address(2)), mySupposedTokens);
        vm.stopPrank();

        // claim extra for address1
        vm.startPrank(address(1), address(1));
        vm.deal(address(1), 0.0002 ether);
        // getExtraETH
        uint256 extraETH = token.getExtraETH(address(1));
        console.log("extra eth: ", extraETH);

        (success, ) = address(token).call{value: 0.0002 ether}("");
        require(success, "transfer failed");

        // check balance of address 1
        assertEq(address(1).balance, 0.0002 ether + extraETH);
        assertEq(
            extraETH,
            (extraEthers * token.fundBalanceOf(address(1))) / totalEthers
        );

        // call again - Failed
        // (success, ) = address(token).call{value: 0.0002 ether}("");
        // require(!success, "transfer failed");
        // vm.expectRevert("FairMint: already claimed");
    }

    receive() external payable {}
}
