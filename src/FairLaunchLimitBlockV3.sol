// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

// IERC20
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Meme} from "./Meme.sol";
import {IFairLaunch, FairLaunchLimitBlockStruct} from "./IFairLaunch.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

interface IUniLocker {
    function lock(
        address lpToken,
        uint256 amountOrId,
        uint256 unlockBlock
    ) external returns (uint256 id);
}

interface IUniswapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}

interface INonfungiblePositionManager {
    function WETH9() external pure returns (address);

    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function refundETH() external payable;

}

contract FairLaunchLimitBlockTokenV3 is
    IFairLaunch,
    Meme,
    ReentrancyGuard,
    NoDelegateCall
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    // refund command
    // before start, you can always refund
    // send 0.0002 ether to the contract address to refund all ethers
    uint256 public constant REFUND_COMMAND = 0.0002 ether;

    // claim command
    // after start, you can claim extra eth
    // send 0.0002 ether to the contract address to claim extra eth
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

    address public immutable uniswapPositionManager;
    address public immutable uniswapFactory;

    // fund balance
    mapping(address => uint256) public fundBalanceOf;

    // is address minted
    mapping(address => bool) public minted;

    // total dispatch amount
    uint256 public immutable totalDispatch;

    // until block number
    uint256 public immutable untilBlockNumber;

    // total ethers funded
    uint256 public totalEthers;

    // soft top cap
    uint256 public immutable softTopCap;

    // refund fee rate
    uint256 public immutable refundFeeRate;

    // refund fee to
    address public immutable refundFeeTo;
    
    // is address claimed extra eth
    mapping(address => bool) public claimed;

    // recipient must be a contract address of IUniLocker
    address public immutable locker;

    // feePool
    uint24 public immutable poolFee;

    // project owner, whill receive the locked lp
    address public immutable projectOwner;

    constructor(
        address _locker,
        uint24 _poolFee,
        address _projectOwner,
        FairLaunchLimitBlockStruct memory params
    ) Meme(params.name, params.symbol, params.meta) {
        started = false;

        totalDispatch = params.totalSupply;
        _mint(address(this), totalDispatch);

        // set uniswap router
        uniswapPositionManager = params.uniswapRouter;
        uniswapFactory = params.uniswapFactory;

        meta = params.meta;

        untilBlockNumber = params.afterBlock + block.number;
        softTopCap = params.softTopCap;

        refundFeeRate = params.refundFeeRate;
        refundFeeTo = params.refundFeeTo;

        locker = _locker;
        projectOwner = _projectOwner;

        poolFee = _poolFee;
    }

    receive() external payable noDelegateCall {
        if (msg.sender == uniswapPositionManager) {
            return;
        }

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
        return block.number >= untilBlockNumber;
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
        uint256 _mintAmount = (totalDispatch * fundBalanceOf[account]) /
            2 /
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
        require(!started, "FairMint: already started");

        address account = msg.sender;
        uint256 amount = fundBalanceOf[account];
        require(amount > 0, "FairMint: no fund");
        fundBalanceOf[account] = 0;
        totalEthers -= amount;
        
        uint256 fee = (amount * refundFeeRate) / 10000;
        assert(fee < amount);

        if (fee > 0 && refundFeeTo != address(0)) {
            (bool success, ) = refundFeeTo.call{value: fee}("");
            require(success, "FairMint: refund fee failed");
        }

        (bool success1, ) = account.call{value: amount - fee + REFUND_COMMAND}(
            ""
        );
        require(success1, "FairMint: refund failed");
        emit RefundEvent(account, 0, amount);
    }

    function _mintToken() private nonReentrant {
        require(started, "FairMint: not started");
        require(msg.sender == tx.origin, "FairMint: can not mint to contract.");
        require(!minted[msg.sender], "FairMint: already minted");

        minted[msg.sender] = true;

        uint256 _mintAmount = mightGet(msg.sender);

        require(_mintAmount > 0, "FairMint: mint amount is zero");
        assert(_mintAmount <= totalDispatch / 2);
        _transfer(address(this), msg.sender, _mintAmount);

        (bool success, ) = msg.sender.call{value: MINT_COMMAND}("");
        require(success, "FairMint: mint failed");
    }

    function _start() private nonReentrant {
        require(!started, "FairMint: already started");
        require(balanceOf(address(this)) > 0, "FairMint: no balance");
        INonfungiblePositionManager _positionManager = INonfungiblePositionManager(
                uniswapPositionManager
            );

        address _weth = _positionManager.WETH9();

        address _poolAddress = IUniswapV3Factory(uniswapFactory).getPool(
            address(this),
            _weth,
            poolFee
        );

        require(
            _poolAddress == address(0),
            "FairMint: pool already exists, can not start, please refund"
        );

        uint256 totalAdd = softTopCap > 0
            ? softTopCap < totalEthers ? softTopCap : totalEthers
            : totalEthers;

        _approve(
            address(this),
            uniswapPositionManager,
            type(uint256).max,
            false
        );

        (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1,

        ) = _initPool(_weth, totalAdd, _positionManager);

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 _amount0,
            uint256 _amount1
        ) = _mintLiquidity(
                _positionManager,
                token0,
                token1,
                amount0,
                amount1,
                totalAdd
            );
        started = true;

        emit LaunchEvent(address(this), _amount0, _amount1, liquidity);
        _positionManager.refundETH();

        // lock lp into contract forever
        if (locker != address(0)) {
            IERC721(uniswapPositionManager).approve(locker, tokenId);
            IUniLocker _locker = IUniLocker(locker);
            uint256 _lockId = _locker.lock(
                uniswapPositionManager,
                tokenId,
                type(uint256).max
            );
            IERC721(locker).transferFrom(address(this), projectOwner, _lockId);
        }

        (bool success, ) = msg.sender.call{value: START_COMMAND}("");
        require(success, "FairMint: mint failed");
    }

    function _mintLiquidity(
        INonfungiblePositionManager _positionManager,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 totalAdd
    ) private returns (uint256, uint128, uint256, uint256) {
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: -887250,
                tickUpper: 887250,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: (amount0 * 98) / 100,
                amount1Min: (amount1 * 98) / 100,
                recipient: locker == address(0) ? address(0) : address(this),
                deadline: block.timestamp + 1 hours
            });

        (
            uint256 _tokenId,
            uint128 _liquidity,
            uint256 _amount0,
            uint256 _amount1
        ) = _positionManager.mint{value: totalAdd}(params);
        _positionManager.refundETH();

        return (_tokenId, _liquidity, _amount0, _amount1);
    }

    function _initPool(
        address _weth,
        uint256 totalAdd,
        INonfungiblePositionManager _positionManager
    )
        private
        returns (
            address token0,
            address token1,
            uint256 amount0,
            uint256 amount1,
            uint160 sqrtPriceX96
        )
    {
        (token0, token1) = address(this) < _weth
            ? (address(this), _weth)
            : (_weth, address(this));

        (amount0, amount1) = address(this) < _weth
            ? (totalDispatch / 2, totalAdd)
            : (totalAdd, totalDispatch / 2);

        sqrtPriceX96 = getSqrtPriceX96(amount0, amount1);

        _positionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            poolFee,
            sqrtPriceX96
        );
    }

    function getSqrtPriceX96(
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint160) {
        require(amount0 > 0 && amount1 > 0, "Amounts must be greater than 0");

        uint256 price = (amount1 * 1e18) / amount0; 
        uint256 sqrtPrice = price.sqrt();
        uint256 sqrtPriceX96Full = (sqrtPrice << 96) / 1e9; 
        return uint160(sqrtPriceX96Full);
    }
}

library Math {
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 result = a;
        uint256 k = a / 2 + 1;
        while (k < result) {
            result = k;
            k = (a / k + k) / 2;
        }
        return result;
    }
}
