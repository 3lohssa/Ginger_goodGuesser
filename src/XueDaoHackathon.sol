// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/contracts/token/ERC20/IERC20.sol";
import "./AggregatorV3Interface.sol";
import "./KeeperCompatible.sol";

contract XueDaoHackathon is KeeperCompatibleInterface {
    struct Guess {
        address user;
        int256 guessedPrice;
        uint256 timestamp;
    }

    address public refundAddress;
    Guess[] public guesses;
    Guess[] public guessesMid;
    Guess[] public guessesMega;
    uint256 public totalAmount;
    uint256 public totalAmountMid;
    uint256 public totalAmountMega;
    uint256 public lastTimestamp;
    uint256 public interval;
    int256 public ethUsdCurrentPrice;
    IERC20 public kjToken; // 添加這一行來引入你的KJ代幣
    uint256 public kjFee; // 手續費數量

    AggregatorV3Interface internal priceFeed;

    event Deposit(address indexed from, uint256 amount);
    event GuessMade(address indexed user, int256 guessedPrice);
    event WinnerSelected(
        address indexed winner,
        uint256 amount,
        string poolType
    );
    event RefundFailed(address indexed winner, uint256 amount, string poolType);
    event PriceUpdated(int256 price);
    event UpkeepPerformed(bool success, uint256 timestamp);

    constructor(
        address _refundAddress,
        uint256 _interval,
        address _priceFeed,
        address _kjTokenAddress,
        uint256 _kjFee
    ) {
        refundAddress = _refundAddress;
        totalAmount = 0;
        totalAmountMid = 0;
        totalAmountMega = 0;
        lastTimestamp = block.timestamp;
        interval = _interval;

        // Initialize Chainlink price feed
        priceFeed = AggregatorV3Interface(_priceFeed);
        //kjtoken
        kjToken = IERC20(_kjTokenAddress); // 初始化KJ代幣地址
        kjFee = _kjFee; // 初始化手續費數量
    }

    receive() external payable {
        require(msg.value > 0, "No ether received");

        if (msg.value == 0.001 ether) {
            totalAmount += msg.value;
        } else if (msg.value == 0.01 ether) {
            totalAmountMid += msg.value;
        } else if (msg.value == 0.1 ether) {
            totalAmountMega += msg.value;
        } else {
            revert("Invalid amount");
        }

        emit Deposit(msg.sender, msg.value);
    }

    function makeGuess(int256 _guessedPrice) public payable {
        require(msg.value == 0.001 ether, "Guess amount is 0.001 ether");

        require(
            kjToken.transferFrom(msg.sender, address(this), kjFee),
            "KJ fee transfer failed"
        );

        guesses.push(
            Guess({
                user: msg.sender,
                guessedPrice: _guessedPrice,
                timestamp: block.timestamp
            })
        );
        totalAmount += msg.value;
        emit GuessMade(msg.sender, _guessedPrice);
    }

    function makeGuessMid(int256 _guessedPrice) public payable {
        require(msg.value == 0.01 ether, "Guess amount is 0.01 ether");

        require(
            kjToken.transferFrom(msg.sender, address(this), kjFee),
            "KJ fee transfer failed"
        );

        guessesMid.push(
            Guess({
                user: msg.sender,
                guessedPrice: _guessedPrice,
                timestamp: block.timestamp
            })
        );
        totalAmountMid += msg.value;
        emit GuessMade(msg.sender, _guessedPrice);
    }

    function makeGuessMega(int256 _guessedPrice) public payable {
        require(msg.value == 0.1 ether, "Guess amount is 0.1 ether");

        require(
            kjToken.transferFrom(msg.sender, address(this), kjFee),
            "KJ fee transfer failed"
        );

        guessesMega.push(
            Guess({
                user: msg.sender,
                guessedPrice: _guessedPrice,
                timestamp: block.timestamp
            })
        );
        totalAmountMega += msg.value;
        emit GuessMade(msg.sender, _guessedPrice);
    }

    function getLatestPrice() public view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price / 1e8;
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        upkeepNeeded =
            ((block.timestamp - lastTimestamp) > interval &&
                guesses.length > 0) ||
            ((block.timestamp - lastTimestamp) > interval &&
                guessesMid.length > 0) ||
            ((block.timestamp - lastTimestamp) > interval &&
                guessesMega.length > 0);
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        if (
            ((block.timestamp - lastTimestamp) > interval &&
                guesses.length > 0) ||
            ((block.timestamp - lastTimestamp) > interval &&
                guessesMid.length > 0) ||
            ((block.timestamp - lastTimestamp) > interval &&
                guessesMega.length > 0)
        ) {
            // Update ETH/USD price
            ethUsdCurrentPrice = getLatestPrice();

            selectWinner();
            lastTimestamp = block.timestamp;
            emit UpkeepPerformed(true, block.timestamp);
        } else {
            emit UpkeepPerformed(false, block.timestamp);
        }
    }

    function selectWinner() private {
        if (guesses.length > 0) {
            selectWinnerForPool(guesses, totalAmount, "Basic");
            delete guesses; // clear guests
        }
        if (guessesMid.length > 0) {
            selectWinnerForPool(guessesMid, totalAmountMid, "Mid");
            delete guessesMid; // clear guestsMid
        }
        if (guessesMega.length > 0) {
            selectWinnerForPool(guessesMega, totalAmountMega, "Mega");
            delete guessesMega; // clear guestsMega
        }
    }

    function selectWinnerForPool(
        Guess[] storage poolGuesses,
        uint256 totalAmountToSend,
        string memory poolType
    ) private {
        require(poolGuesses.length > 0, "No participants");

        address winner = address(0);
        int256 closestDifference = type(int256).max;
        uint256 earliestTimestamp = type(uint256).max;

        for (uint i = 0; i < poolGuesses.length; i++) {
            int256 difference = poolGuesses[i].guessedPrice > ethUsdCurrentPrice
                ? poolGuesses[i].guessedPrice - ethUsdCurrentPrice
                : ethUsdCurrentPrice - poolGuesses[i].guessedPrice;

            if (
                difference < closestDifference ||
                (difference == closestDifference &&
                    poolGuesses[i].timestamp < earliestTimestamp)
            ) {
                closestDifference = difference;
                earliestTimestamp = poolGuesses[i].timestamp;
                winner = poolGuesses[i].user;
            }
        }

        require(winner != address(0), "No winner selected");

        // Update pool amount only after sending the funds
        uint256 amountToSend = totalAmountToSend;
        if (keccak256(bytes(poolType)) == keccak256(bytes("Basic"))) {
            totalAmount = 0;
        } else if (keccak256(bytes(poolType)) == keccak256(bytes("Mid"))) {
            totalAmountMid = 0;
        } else if (keccak256(bytes(poolType)) == keccak256(bytes("Mega"))) {
            totalAmountMega = 0;
        }

        (bool success, ) = winner.call{value: amountToSend, gas: 50000}("");
        if (success) {
            emit WinnerSelected(winner, amountToSend, poolType);
        } else {
            emit RefundFailed(winner, amountToSend, poolType);
        }
    }

    function withdraw() external {
        require(
            msg.sender == refundAddress,
            "Only the refund address can withdraw"
        );
        payable(refundAddress).transfer(address(this).balance);
    }
}
