// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// IMPORTS ------------------------------------------------------------------------------------
/// @notice debugging tool
import "hardhat/console.sol";
/// @notice random Number oracle
/// @dev using v1 VRF
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
/// @notice restricted access
import "@openzeppelin/contracts/access/Ownable.sol";
/// @notice security
/// @dev security against transactions with multiple requests
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// ERROR MESSAGES ------------------------------------------------------------------

// CONTRACTS ------------------------------------------------------------------------------------
/// @title Lottery
/// @author Stefan Lehmann/Stefan1612/SimpleBlock
/// @notice Contract utilizing Chainlink's VRF to generate a truly random result for a lottery
/// @dev testing in local environment would be either done via: 1. changing this contract to create random numbers without VRF for testing purposes. 2. using the provided Mock. 3. Forking Mainnet.
contract Lottery is Ownable, ReentrancyGuard, VRFConsumerBase {
   
    // @Dev constructor  @arg:
    //kovan:
    //vrf: 0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9,
    //link: 0xa36085F69e2889c224210F603D836748e7dC0088,
    //keyHash: 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4,
    //Fee: 1000000000000000000

    // Type declarations, State Variables --------------------------------------------------------------------------
    /// @notice total amount of wei in the current running lottery pool
    uint256 public s_totalCurrentPool;

    /// @notice time the lottery will be running for
    uint256 public time = 10 seconds;

    /// @dev coming from Chainlink's VRF
    bytes32 internal keyHash;
    uint256 internal fee;
    /// @notice the random result used to declare winners
    uint256 public randomResult;

    /// @notice keeping track of the past winnings of individuals to withdraw
    mapping(address => uint256) public winners;

    /// @notice The block.timestamp starting time of the current lottery
    uint256 public startTime;

    /// @notice the unix time when the lottery has the OPTION to end (lottery needs to have atleast 2 participants and the timer to be over to stop)
    uint256 public endTime;

    /// @notice lottery entry price
    uint256 public price = 0.002 ether;

    /// @notice winner of the last lottery
    address payable public winner;

    /// @notice to make sure that only ONE lottery gets run at a time 
    /// @dev alternative would be enum
    bool private winnerChosen = false;

    /// @notice everyone in the currently running lottery
    address payable[] public participants;

    uint256 private lotteryProfits;

    // EVENTS ------------------------------------------------------------------------------------
    /// @notice triggers after lottery entry price changes
    event priceChange(
        uint indexed newPrice
    );

    /// @notice lottery time interval change
    event timeChange(
        uint indexed newTime
    );

    /// @notice emitting lottery ended, winner, and his price
    event winnerHasBeenChosen(
        address indexed _winner,
        uint256 indexed totalWinning,
        uint256 indexed time
    );

    /// @notice new Lottery started
    event newLotteryStarted(uint256 indexed time);

    /// @notice someone entered the lottery (multiple entry of same address allowed)
    event newParticipant(address indexed newEntry, uint256 indexed time);

    // MODIFIERS ------------------------------------------------------------------------------------
    /// @notice restricting time to join and a minimun of participants, else you cannot draw a winner
    modifier onlyWhile(uint256 _time) {
        require(
            _time >= block.timestamp || participants.length < 2,
            "You cannot enter this pool anymore"
        );
        _;
    }

    /// @notice making sure the EXACT entry price is transfered
    modifier entryPrice() {
        require(msg.value == price, "You need to pay the exact price");
        _;
    }

    /// @notice checking if lottery time has ran out
    modifier onlyAfter(uint256 _time) {
        require(_time <= block.timestamp, "The lottery has not ended yet");
        _;
    }

    // FUNCTIONS ------------------------------------------------------------------------------------
    /// @param vrfCoordinator, link, _keyhash, _fee are all predetermined by chainlink: https://docs.chain.link/docs/get-a-random-number/v1/
    /// @dev VRF1, reentrancy, and ownable
    constructor(
        address vrfCoordinator,
        address link,
        bytes32 _keyHash,
        uint256 _fee
    ) VRFConsumerBase(vrfCoordinator, link) Ownable() ReentrancyGuard() {
        keyHash = _keyHash;
        fee = _fee;
        startTime = block.timestamp;
        endTime = block.timestamp + time;
    }

    /// @dev if somebody accidentally sends ether directly to the contract
    fallback() payable external {
        enterPool();
    }

    /// @notice used as help for the front-end
    function getArrayLength() external view returns (uint256 length) {
        length = participants.length;
    }

    /// @notice
    /// @param newTime the new time amount you want the lottery to be running for
    function settingTimeInSeconds(uint256 newTime) external onlyOwner {
        require(
            winnerChosen == true,
            "You can only change the time after the winner has been chosen!"
        );
        time = newTime;
        emit timeChange(time);
    }

    /// @notice changing entry price
    function entryPriceInWei(uint256 newPrice) external onlyOwner {
        require(
            winnerChosen == true,
            "You can only change the entry price after the winner has been chosen!"
        );
        price = newPrice;
        emit priceChange(price);
    }

    /// @notice function to enter the current lottery
    function enterPool()
        public
        payable
        entryPrice
        onlyWhile(startTime + time)
    {
        require(winnerChosen == false, "A new lottery has to be started");

        //multiple entry allowed
        participants.push(payable(msg.sender));
        s_totalCurrentPool += price;
        emit newParticipant(msg.sender, block.timestamp);
    }

    /// @notice start of generating random number
    /// @dev activating the VRF call
    function getRandomNumber() private returns (bytes32 requestId) {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        return requestRandomness(keyHash, fee);
    }

    /// @notice receiving random num
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = (randomness % participants.length);
        secondPartChoose(randomResult);
    }

    /// @notice choosing the winner of the current lottery
    function chooseWinner() external onlyOwner onlyAfter(startTime + time) {
        require(
            participants.length >= 2,
            "There are not enough participants yet"
        );
        require(winnerChosen == false, "The time has not run out yet");

        //Cut this:
        getRandomNumber();
        //cut end

        //Non oracle solution
        // @Dev Uncomment and cut the getRandomNumber(), line 141 right above this

        //uncomment for non-oracle testing purposes
        /*uint256 range = participants.length;

        uint256 winnerIndex = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.difficulty, msg.sender)
            )
        ) % range;

        winner = payable(participants[winnerIndex]);

        // 10% profit cut for contract
        winners[winner] += (s_totalCurrentPool * 9) / 10;
        lotteryProfits += (s_totalCurrentPool * 1) / 10;

        // clearing the participant list
        delete participants;

        // emit that winner has been chosen and he can retrieve his winnings
        emit winnerHasBeenChosen(winner, s_totalCurrentPool, block.timestamp);
        s_totalCurrentPool = 0;
        winnerChosen = true;*/
    }

    // also cut this for non-oracle:
    /// @notice second part of choosing a random Winner
    function secondPartChoose(uint256 _randomResult) private {
        //oracle solution

        //winner = payable(participants[winnerIndex]);
        winner = payable(participants[_randomResult]);

        // 10% profit cut for contract
        winners[winner] += (s_totalCurrentPool * 9) / 10;
        lotteryProfits += (s_totalCurrentPool * 1) / 10;

        // clearing the participant list
        delete participants;

        // emit that winner has been chosen and he can retrieve his winnings
        emit winnerHasBeenChosen(winner, s_totalCurrentPool, block.timestamp);
        s_totalCurrentPool = 0;
        winnerChosen = true;
    }

    //cut end

    /// @notice Starting a new Lottery
    function startNewLottery() external onlyOwner {
        require(
            winnerChosen == true,
            "You need to choose the winner for the current Lottery, before you can start a new one"
        );
        // resetting the timestamp will automatically start a new lottery
        startTime = block.timestamp;
        endTime = block.timestamp + time;
        winnerChosen = false;
        winner = payable(address(0));
        emit newLotteryStarted(block.timestamp);
    }

    /// @notice function to withdraw your price money
    /// @param _receiver receiver address of the price money
    function withdrawPrice(address payable _receiver) external nonReentrant {
        require(winners[msg.sender] > 0, "You have not won a lottery yet");
        //winners[msg.sender] =0;
        (bool sent, ) = _receiver.call{value: winners[msg.sender]}("");
        require(sent, "Failed to send Ether");
        winners[msg.sender] = 0;
    }

    /// @notice getting info about the current balance the contract holds
    function getBalance() external view returns (uint256 contractBalance) {
        contractBalance = address(this).balance;
    }

    /// @notice owner of the lottery contract can withdraw his "cut"
    function lotteryProfitsWithdraw() external onlyOwner nonReentrant {
        require(lotteryProfits > 0, "No profits to take");
        //lotteryProfits = 0;
        (bool sent, ) = msg.sender.call{value: lotteryProfits}("");
        require(sent, "Failed to send Ether");
        lotteryProfits = 0;
    }
}
