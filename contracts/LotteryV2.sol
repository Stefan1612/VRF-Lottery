// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// IMPORTS ------------------------------------------------------------------------------------
/// @notice debugging tool
import "hardhat/console.sol";
/// @notice random Number oracle
/// @dev using v1 VRF
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
/// @notice restricted access
// import "@openzeppelin/contracts/access/Ownable.sol";
/// @notice security
/// @dev security against transactions with multiple requests
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// ERROR MESSAGES ------------------------------------------------------------------
error Lottery__LotteryCannotBeEnteredAtThisPointOfTime(uint timestamp);
error Lottery__DidNotPayExactEntryPrice(address sender, uint valueSend);
error Lottery__LotteryAlreadyEnded(address caller );
error Lottery__LotteryHasNoWinnerYet(address caller);
error Lottery__CurrentlyNoLotteryRunning(address requester);
error Lottery__NotEnoughLotteryParticipants(uint participantsLength);
error Lottery__WinnerAlreadyChosen(bool winnerChosen);
error Lottery__FailedSendingEther( address caller, uint valueSend);
error Lottery__CallerDidNotWinALottery(address caller);
error Lottery__CallerHasNoProfits(address caller);
error Lottery__LotteryHasNotEndedYet(address caller);

// CONTRACTS ------------------------------------------------------------------------------------
/// @title Lottery
/// @author Stefan Lehmann/Stefan1612/SimpleBlock
/// @notice Contract utilizing Chainlink's VRF to generate a truly random result for a lottery
/// @dev testing in local environment would be either done via: 1. changing this contract to create random numbers without VRF for testing purposes. 2. using the provided Mock. 3. Forking Mainnet.
contract LotteryV2 is  ReentrancyGuard, VRFConsumerBaseV2, ConfirmedOwner  {
   
    /*
    @Dev constructor arguments:
    goerli VRF V2

    link token: 0x326c977e6efc84e512bb9c30f76e30c160ed06fb
    Key hash: 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
    Max gas price: 150 Gwei
    VRF Coordinator: 	0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
    */

    // Type declarations, State Variables --------------------------------------------------------------------------
    /// @notice total amount of wei in the current running lottery pool
    uint256 public s_totalCurrentPool;

    /// @notice time the lottery will be running for
    uint256 public time = 10 seconds;

    /// @dev coming from Chainlink's VRF
   // bytes32 private keyHash;
    uint256 internal fee;

    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }

    mapping(uint256 => RequestStatus)
        public s_requests; /* requestId --> requestStatus */
    VRFCoordinatorV2Interface COORDINATOR;

    // Your subscription ID.
    uint64 s_subscriptionId;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    // this would be hardcoded for goerli but can be changed if needed through constructor
    bytes32 keyHash =
        0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    uint32 callbackGasLimit = 300000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 1 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords = 1;


    enum lotteryState {
        lookingForPariticipants,
        endedNoWinnerChosen,
        currentlyChoosingWinner,
        WinnerChosenWaitingToBeStarted
    }

    lotteryState public currentState = lotteryState.lookingForPariticipants;



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
     /*  // In Case modifiers and requires get more gas efficient in the future
    /// @notice restricting time to join and a minimun of participants, else you cannot draw a winner
   /*  modifier onlyWhile(uint256 _time) {
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
    } */

    // FUNCTIONS ------------------------------------------------------------------------------------
    /// @param vrfCoordinator, link, _keyhash, _fee are all predetermined by chainlink: https://docs.chain.link/docs/get-a-random-number/v1/
    /// @dev VRF1, reentrancy, and ownable
    /**
     * FOR GOERLI
     * COORDINATOR: 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
     keyhash: 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15
     */
    constructor(
        uint64 subscriptionId,
        address _VRFCoordinatorAddress,
        bytes32 _keyHash
        //_fee
    ) VRFConsumerBaseV2(_VRFCoordinatorAddress)
        ConfirmedOwner(msg.sender)  
        // Ownable() 
        ReentrancyGuard() {

        keyHash = _keyHash;
        //fee = _fee;
        startTime = block.timestamp;
        endTime = block.timestamp + time;
        COORDINATOR = VRFCoordinatorV2Interface(
            0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
        );
        s_subscriptionId = subscriptionId;
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
    /// @dev possible modfier "onlyOwner" (some form of restricted access should be provided, alternative could be a dao handling the entry price)
    function settingTimeInSeconds(uint256 newTime) external  {
        /* require(
            winnerChosen == true,
            "You can only change the time after the winner has been chosen!"
        ); */
        if(!winnerChosen == true){
            revert Lottery__LotteryHasNoWinnerYet(msg.sender);
        }
        time = newTime;
        emit timeChange(time);
    }

    /// @notice changing entry price
    /// @param newPrice new entry price of the lottery
    /// @dev possible modfier "onlyOwner" (some form of restricted access should be provided, alternative could be a dao handling the entry price)
    function entryPriceInWei(uint256 newPrice) external  {
        /* require(
            winnerChosen == true,
            "You can only change the entry price after the winner has been chosen!"
        ); */
        if(!winnerChosen == true){
            revert Lottery__LotteryHasNoWinnerYet(msg.sender);
        }
        price = newPrice;
        emit priceChange(price);
    }

    /// @notice function to enter the current lottery
    /// @dev potential modifiers if custom error messages stopped being more gas efficient: entryPrice, onlyWhile(startTime + time)
    function enterPool()
        public
        payable
        
    {
        /* require(winnerChosen == false, "A new lottery has to be started"); */
        if(!winnerChosen == false){
            revert Lottery__CurrentlyNoLotteryRunning(msg.sender);
        }
        if(msg.value != price){
            revert Lottery__DidNotPayExactEntryPrice(msg.sender, msg.value);
        }
        if(startTime + time < block.timestamp && participants.length >= 2){
            revert Lottery__LotteryCannotBeEnteredAtThisPointOfTime(block.timestamp);
        }
        //multiple entry allowed
        participants.push(payable(msg.sender));
        s_totalCurrentPool += price;
        emit newParticipant(msg.sender, block.timestamp);
    }

    


    /// @notice start of generating random number
    /// @dev activating the VRF call
    function requestRandomWords() private returns (uint256 requestId) {
       
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
     
        lastRequestId = requestId;
   
        emit RequestSent(requestId, numWords);
        return requestId;
      
    }

    /// @notice receiving random num
    function fulfillRandomWords( uint256 _requestId,
        uint256[] memory _randomWords)
        internal
        override
    {   

  
        emit RequestFulfilled(_requestId, _randomWords);

        randomResult = (_randomWords[0] % participants.length);

        secondPartChoose(randomResult);
    }

    /// @notice choosing the winner of the current lottery
     /// @dev potential modifiers if custom error messages stopped being more gas efficient: onlyAfter(startTime + time)
    function chooseWinner() external  {
        // replacement for "onlyAfter(startTime + time) modifier
        currentState = lotteryState.currentlyChoosingWinner;
        /* if(startTime + time < block.timestamp){
            revert Lottery__LotteryHasNotEndedYet(msg.sender);
        } */
        
        /* require(
            participants.length >= 2,
            "There are not enough participants yet"
        ); */
        /* if(participants.length < 2){
            revert Lottery__LotteryHasNotEndedYet(msg.sender);
        } */

        /* require(winnerChosen == false, "The time has not run out yet"); */
        /* if(winnerChosen == true){
            revert Lottery__WinnerAlreadyChosen(winnerChosen);
        } */
     
        //Cut this:
        requestRandomWords();
        //cut end

        //Non oracle solution
        // @Dev Uncomment and cut the getRandomNumber(), line 141 right above this

        //uncomment for non-oracle testing purposes
      /*   uint256 range = participants.length;

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
        winnerChosen = true; */
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
        winnerChosen = true;
         currentState = lotteryState.WinnerChosenWaitingToBeStarted;
        // emit that winner has been chosen and he can retrieve his winnings
        emit winnerHasBeenChosen(winner, s_totalCurrentPool, block.timestamp);
        s_totalCurrentPool = 0;
        
    }

    //cut end

    /// @notice Starting a new Lottery
    function startNewLottery() external  {
        /* require(
            winnerChosen == true,
            "You need to choose the winner for the current Lottery, before you can start a new one"
        ); */
        if(!winnerChosen == true){
            revert Lottery__LotteryHasNoWinnerYet(msg.sender);
        }
        // resetting the timestamp will automatically start a new lottery
        startTime = block.timestamp;
        endTime = block.timestamp + time;
        winnerChosen = false;
        winner = payable(address(0));
        currentState = lotteryState.WinnerChosenWaitingToBeStarted;
        emit newLotteryStarted(block.timestamp);
    }

    /// @notice function to withdraw your price money
    /// @param _receiver receiver address of the price money
    function withdrawPrice(address payable _receiver) external nonReentrant {
        /* require(winners[msg.sender] > 0, "You have not won a lottery yet"); */
        if(winners[msg.sender] <= 0){
            revert Lottery__CallerDidNotWinALottery(msg.sender);
        }
        
        (bool sent, ) = _receiver.call{value: winners[msg.sender]}("");
        if(!sent){
            revert Lottery__FailedSendingEther(msg.sender, winners[msg.sender]);
        }
        /* require(sent, "Failed to send Ether"); */
        winners[msg.sender] = 0;
    }

    /// @notice getting info about the current balance the contract holds
    function getBalance() external view returns (uint256 contractBalance) {
        contractBalance = address(this).balance;
    }

    /// @notice owner of the lottery contract can withdraw his "cut"
    
    function lotteryProfitsWithdraw() external onlyOwner nonReentrant {
        /* require(lotteryProfits > 0, "No profits to take"); */
        
        if(lotteryProfits <= 0){
            revert Lottery__CallerHasNoProfits(msg.sender);
        }
     
        (bool sent, ) = msg.sender.call{value: lotteryProfits}("");
        if(!sent){
            revert Lottery__FailedSendingEther(msg.sender, lotteryProfits);
        }
        /* require(sent, "Failed to send Ether"); */
        lotteryProfits = 0;
    }
}
