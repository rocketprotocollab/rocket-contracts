// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

// IERC20
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Meme} from "./Meme.sol";
import {IFairLaunch, FairLaunchLimitBlockStruct} from "./IFairLaunch.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IUniswapV2Factory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);

    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

contract FairLaunchLimitBlockToken is IFairLaunch, Meme, ReentrancyGuard, NoDelegateCall {
    using SafeERC20 for IERC20;

    // refund command
    // before start, you can always refund
    // send 0.0002 ether to the contract address to refund all ethers
    uint256 public constant REFUND_COMMAND = 0.0002 ether;

    uint256 public constant CLAIM_COMMAND = 0.0002 ether;

    // start trading command
    // if the untilBlockNumber reached, you can start trading with this command
    // send 0.0005 ether to the contract address to start trading
    uint256 public constant START_COMMAND = 0.0005 ether;

    // mint command
    // if the untilBlockNumber reached, you can mint token with this command
    // send 0.0001 ether to the contract address to get tokens
    uint256 public constant MINT_COMMAND = 0.0001 ether;

    // minimal fund
    uint256 public constant MINIMAL_FUND = 0.0001 ether;

    // is trading started
    bool public started;

    address immutable public uniswapRouter;
    address immutable public uniswapFactory;

    // fund balance
    mapping(address => uint256) public fundBalanceOf;

    // is address minted
    mapping(address => bool) public minted;

    // total dispatch amount
    uint256 immutable public totalDispatch;

    // until block number
    uint256 immutable public untilBlockNumber;

    // total ethers funded
    uint256 public totalEthers;

    // soft top cap
    uint256 immutable public softTopCap;

    // refund fee rate
    uint256 immutable public refundFeeRate;

    // refund fee to
    address immutable public refundFeeTo;

    mapping(address => bool) public claimed;

    constructor(
        FairLaunchLimitBlockStruct memory params
    ) Meme(params.name, params.symbol, params.meta) {
        started = false;

        totalDispatch = params.totalSupply;
        _mint(address(this), totalDispatch);

        // set uniswap router
        uniswapRouter = params.uniswapRouter;
        uniswapFactory = params.uniswapFactory;

        meta = params.meta;

        untilBlockNumber = params.afterBlock + block.number;
        softTopCap = params.softTopCap;

        refundFeeRate = params.refundFeeRate;
        refundFeeTo = params.refundFeeTo;
    }

    receive() external payable noDelegateCall {
        require(
            tx.origin == msg.sender,
            "FairMint: can not send command from contract."
        );
        if (started) {
            // after started
            if (msg.value == MINT_COMMAND) {
                // mint token
                _mintToken();
            } else if (msg.value == CLAIM_COMMAND) {
                _claimExtraETH();
            } else {
                revert("FairMint: invalid command - mint or claim only");
            }
        } else {
            // before started
            if (canStart()) {
                if (msg.value == REFUND_COMMAND) {
                    // before start, you can always refund
                    _refund();
                } else if (msg.value == START_COMMAND) {
                    // start trading, add liquidity to uniswap
                    _start();
                } else {
                    revert("FairMint: invalid command - start or refund only");
                }
            } else {
                if (msg.value == REFUND_COMMAND) {
                    // before start, you can always refund
                    _refund();
                } else {
                    // before start, any other value will be considered as fund
                    _fund();
                }
            }
        }
    }

    function canStart() public view returns (bool) {
        // return block.number >= untilBlockNumber || totalEthers >= softTopCap;
        // eth balance of this contract is more than zero
        return block.number >= untilBlockNumber && balanceOf(address(this)) > 0 && totalEthers >= MINIMAL_FUND;
    }

    // get extra eth
    function getExtraETH(address _addr) public view returns (uint256) {
        if (totalEthers > softTopCap) {
            uint256 claimAmount = (fundBalanceOf[_addr] *
                (totalEthers - softTopCap)) / totalEthers;
            return claimAmount;
        }
        return 0;
    }

    // claim extra eth
    function _claimExtraETH() private nonReentrant {
        // if the eth balance of this contract is more than soft top cap, withdraw it
        // must after start
        require(started, "FairMint: withdraw extra eth must after start");
        require(softTopCap > 0, "FairMint: soft top cap must be set");
        require(totalEthers > softTopCap, "FairMint: no extra eth");
        require(msg.value == CLAIM_COMMAND, "FairMint: value not match");

        uint256 extra = totalEthers - softTopCap;
        uint256 fundAmount = fundBalanceOf[msg.sender];
        require(fundAmount > 0, "FairMint: no fund");

        require(!claimed[msg.sender], "FairMint: already claimed");
        claimed[msg.sender] = true;

        uint256 claimAmount = (fundAmount * extra) / totalEthers;

        // send to msg sender
        (bool success, ) = msg.sender.call{value: claimAmount + CLAIM_COMMAND}(
            ""
        );
        require(success, "FairMint: withdraw failed");
    }

    // estimate how many tokens you might get
    function mightGet(address account) public view returns (uint256) {
        if (totalEthers == 0) {
            return 0;
        }
        uint256 _mintAmount = (totalDispatch * fundBalanceOf[account]) / 2 /
            totalEthers;
        return _mintAmount;
    }

    function _fund() private nonReentrant {
        // require msg.value > 0.0001 ether
        require(!started, "FairMint: already started");
        require(msg.value >= MINIMAL_FUND, "FairMint: value too low");
        fundBalanceOf[msg.sender] += msg.value;
        totalEthers += msg.value;
        emit FundEvent(msg.sender, msg.value, 0);
    }

    function _refund() private nonReentrant {
        require(msg.value == REFUND_COMMAND, "FairMint: value not match");
        require(!started, "FairMint: already started");

        address account = msg.sender;
        uint256 amount = fundBalanceOf[account];
        require(amount > 0, "FairMint: no fund");
        fundBalanceOf[account] = 0;
        totalEthers -= amount;
        // payable(account).transfer(amount + REFUND_COMMAND);
        // transfer only have limited gas, so we use call for refund test
        // refund fee
        uint256 fee = (amount * refundFeeRate) / 10000;
        assert(fee < amount);

        if (fee > 0 && refundFeeTo != address(0)) {
            (bool success, ) = refundFeeTo.call{value: fee}("");
            require(success, "FairMint: refund fee failed");
        }

        (bool success1, ) = account.call{value: amount - fee + REFUND_COMMAND}("");
        require(success1, "FairMint: refund failed");
        emit RefundEvent(account, 0, amount);
    }

    function _mintToken() private  nonReentrant {
        require(started, "FairMint: not started");
        require(msg.value == MINT_COMMAND, "FairMint: value not match");
        require(msg.sender == tx.origin, "FairMint: can not mint to contract.");
        require(!minted[msg.sender], "FairMint: already minted");

        minted[msg.sender] = true;

        uint256 _mintAmount = mightGet(msg.sender);

        require(_mintAmount > 0, "FairMint: mint amount is zero");
        assert(_mintAmount <= totalDispatch / 2);
        _transfer(address(this), msg.sender, _mintAmount);

        // payable(msg.sender).transfer(MINT_COMMAND);
        // transfer only have limited gas, so we use call for refund test
        (bool success, ) = msg.sender.call{value: MINT_COMMAND}("");
        require(success, "FairMint: mint failed");
    }

    function _start() private nonReentrant {
        require(!started, "FairMint: already started");
        address _weth = IUniswapV2Router02(uniswapRouter).WETH();
        address _pair = IUniswapV2Factory(uniswapFactory).getPair(
            address(this),
            _weth
        );

        if (_pair == address(0)) {
            _pair = IUniswapV2Factory(uniswapFactory).createPair(
                address(this),
                _weth
            );
        }
        _pair = IUniswapV2Factory(uniswapFactory).getPair(address(this), _weth);
        assert(_pair != address(0));
        // set started
        started = true;

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);
        _approve(address(this), uniswapRouter, type(uint256).max);

        uint256 totalAdd = softTopCap > 0
            ? softTopCap < totalEthers ? softTopCap : totalEthers
            : totalEthers;

        // add liquidity
        (uint256 tokenAmount, uint256 ethAmount, uint256 liquidity) = router
        // .addLiquidityETH{value: address(this).balance}(
            .addLiquidityETH{value: totalAdd}(
            address(this), // token
            totalDispatch / 2, // token desired
            totalDispatch / 2, // token min
            totalAdd, // eth min
            address(0), // lp to, if you want to drop 
            block.timestamp + 1 days // deadline
        );
        emit LaunchEvent(address(this), tokenAmount, ethAmount, liquidity);

        (bool success, ) = msg.sender.call{value: START_COMMAND}("");
        require(success, "FairMint: mint failed");
    }
}
