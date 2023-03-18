pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BTCBet is Ownable {
    uint256 public constant BET_EXPIRATION = 3 months;
    uint256 public constant TARGET_PRICE = 1000000 * 10**8; // $1M in 8 decimal format
    uint256 public betEndTime;

    AggregatorV3Interface public priceFeedBTC;
    IERC20 public usdcToken;

    enum Bet {NotPlaced, Bullish, Bearish}
    mapping(address => Bet) public bets;
    mapping(Bet => uint256) public totalBets;

    event BetPlaced(address indexed user, Bet bet, uint256 amount);
    event BetSettled(address indexed user, uint256 amount);

    constructor(address _priceFeedBTC, address _usdcToken) {
        priceFeedBTC = AggregatorV3Interface(_priceFeedBTC);
        usdcToken = IERC20(_usdcToken);
        betEndTime = block.timestamp + BET_EXPIRATION;
    }

    function placeBet(Bet _bet, uint256 _amount) external {
        require(block.timestamp < betEndTime, "Betting period has ended");
        require(_bet != Bet.NotPlaced, "Invalid bet");
        require(bets[msg.sender] == Bet.NotPlaced, "Bet already placed");
        require(_amount > 0, "Amount must be greater than 0");
        require(usdcToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

        bets[msg.sender] = _bet;
        totalBets[_bet] += _amount;

        emit BetPlaced(msg.sender, _bet, _amount);
    }

    function settleBet() external {
        require(block.timestamp >= betEndTime, "Betting period not yet ended");
        require(bets[msg.sender] != Bet.NotPlaced, "No bet placed");

        (, int256 price, , ,) = priceFeedBTC.latestRoundData();
        require(price > 0, "Invalid price data");

        uint256 payout = 0;
        Bet winningBet = (price >= TARGET_PRICE) ? Bet.Bullish : Bet.Bearish;

        if (bets[msg.sender] == winningBet) {
            uint256 loserAmount = totalBets[winningBet == Bet.Bullish ? Bet.Bearish : Bet.Bullish];
            uint256 winnerAmount = totalBets[winningBet];
            uint256 totalPool = loserAmount + winnerAmount;

            payout = (usdcToken.balanceOf(address(this)) * totalBets[msg.sender]) / totalPool;
            require(usdcToken.transfer(msg.sender, payout), "Transfer failed");
        }

        bets[msg.sender] = Bet.NotPlaced;
        emit BetSettled(msg.sender, payout);
    }

    function withdraw(uint256 _amount) external onlyOwner {
        require(usdcToken.transfer(msg.sender, _amount), "Transfer failed");
    }

    function getLatestPrice() public view returns (int256) {
        (, int256 price, , ,) = priceFeedBTC.latestRoundData();
        return price;
    }
}
