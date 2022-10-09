// SPDX-License-Identifier: MIT
// Referenced and heavily modified from pancakeswap prediction mini game on binance smart chain


pragma solidity ^0.8.7;

// REMIX IMPORTS

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";


// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol"; // delete in production

contract SaltyPredict is Ownable, Pausable, ReentrancyGuard {
   using SafeERC20 for IERC20;


   uint256 public minBetAmount; // minimum betting amount (denominated in wei)
   uint256 public curEpoch; // current epoch for prediction round
   uint256 public prevRound; // previous round id
   uint256 public curRound; // current round id
   address public adminAddress; // admin owner
   uint256 public treasuryAmount; // treasury amount that was not claimed
   uint256 public treasuryFee;
   uint256 public someVar; // some var

   mapping(uint256 => mapping(address => BetInfo)) public ledger; // ledger of previous matches, including players and bets
   mapping(uint256 => Round) public rounds;
   mapping(address => uint256[]) public userRounds;

    // red (BEAR) = 0, blue (BULL) = 1
    enum Position {
        Red,
        Blue
    }

    struct Round {
        bytes32 id;
        uint256 epoch;
        uint256 redAmount;
        uint256 blueAmount;
        uint256 totalAmount;
        uint256 winningPlayer;
        uint256 startTimestamp;
        uint256 closeTimestamp;
        uint256 rewardBaseCalAmount;
        uint256 rewardAmount;
        bool oracleCalled;
    }

    struct BetInfo {
        Position position;
        uint256 amount;
        bool claimed;
    }

    event BetRed(address indexed sender, uint256 indexed epoch, uint256 amount);
    event BetBlue(address indexed sender, uint256 indexed epoch, uint256 amount);
    event Claim(address indexed sender, uint256 indexed epoch, uint256 amount);
    event StartRound(uint256 indexed epoch);
    event Pause(uint256 indexed epoch);
    //event RewardsCalculated(uint256 indexed epoch, uint256 indexed rewardBaseCalAmount, uint256 indexed rewardAmount, uint256 indexed treasuryAmt);

    constructor(){
        adminAddress = msg.sender;
        treasuryFee = 1000; // 10%
    }

    function betRed(uint256 epoch) external payable whenNotPaused nonReentrant {
        require(epoch == curEpoch, "Bet is too early/late");
        require(msg.value >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(ledger[epoch][msg.sender].amount == 0, "Can only bet once per round");

        // Update round data
        uint256 amount = msg.value;
        Round storage round = rounds[epoch];
        require(block.timestamp <= round.startTimestamp + 45 seconds, "Round Not Bettable"); // added new
        round.totalAmount = round.totalAmount + amount;
        round.redAmount = round.redAmount + amount;

        // Update user data
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        betInfo.position = Position.Red;
        betInfo.amount = amount;
        userRounds[msg.sender].push(epoch);

        emit BetRed(msg.sender, epoch, amount);
    }

    function someVarTest(uint256 someNumber) public returns (uint256) {
        someVar = someNumber;
        return someVar;
    }

    function betBlue(uint256 epoch) external payable whenNotPaused nonReentrant {
        require(epoch == curEpoch, "Bet is too early/late");
        require(msg.value >= minBetAmount, "Bet amount must be greater than minBetAmount");
        require(ledger[epoch][msg.sender].amount == 0, "Can only bet once per round");

        // Update round data
        uint256 amount = msg.value;
        Round storage round = rounds[epoch];
        require(block.timestamp <= round.startTimestamp + 45 seconds, "Round Not Bettable"); // added new
        round.totalAmount = round.totalAmount + amount;
        round.blueAmount = round.blueAmount + amount;

        // Update user data
        BetInfo storage betInfo = ledger[epoch][msg.sender];
        betInfo.position = Position.Blue;
        betInfo.amount = amount;
        userRounds[msg.sender].push(epoch);

        emit BetBlue(msg.sender, epoch, amount);
    }

    
    /**
     * Send funds direct to contract for it to disperse them to winners I believe?
     * @notice Claim reward for an array of epochs
     * @param epochs: array of epochs
     */
    function claim(uint256[] calldata epochs) external nonReentrant {
        uint256 reward; // Initializes reward
                    

        for (uint256 i = 0; i < epochs.length; i++) { // starts at epoch 1??????
           
            require(rounds[epochs[i]].startTimestamp != 0, "Round has not started");
            require(block.timestamp > rounds[epochs[i]].closeTimestamp, "Round has not ended");

            uint256 addedReward = 0;
            
            // Round valid, claim rewards
            if (rounds[epochs[i]].oracleCalled) {
                //console.log("Claim() ROUNDS EPOCH i: ", i);
                //console.log("------------------------");
                
                require(claimable(epochs[i], msg.sender), "Not eligible for claim");
                Round memory round = rounds[epochs[i]];
                
                //console.log("Round reward base calc amount", round.rewardBaseCalAmount);

                // cannot claim from epoch/round 0, only can claim from epoch/round 1+ (there is no round 0) still abit confused
                if(round.rewardBaseCalAmount != 0){
                addedReward = (ledger[epochs[i]][msg.sender].amount * round.rewardAmount) / round.rewardBaseCalAmount;
                }
                //console.log("Added reward calculated value: ", addedReward);
            }
            // Round invalid, refund bet amount
            else {
                require(refundable(epochs[i], msg.sender), "Not eligible for refund");
                addedReward = ledger[epochs[i]][msg.sender].amount;
            }

            ledger[epochs[i]][msg.sender].claimed = true;
            reward += addedReward;

            emit Claim(msg.sender, epochs[i], addedReward);
        }

        if (reward > 0) {
            // console.log("================================");
            // console.log("================================");
            // console.log("REWARD AMOUNT HERE BEFORE SEND", reward);
            _safeTransferBNB(address(msg.sender), reward);
            //reward   (HERE ITS SENDING TOO MUCH FOR SOME REASON? DOUBLE CHECK CALC WRONG) 0.8 eth win
            // reward = 1800000000000000000000000000000000000???? wtf
        }
    }

        /**
     * @notice Transfer BNB in a safe way
     * @param to: address to transfer BNB to
     * @param value: BNB amount to transfer (in wei)
     */
    function _safeTransferBNB(address to, uint256 value) internal {
        // console.log("_SAFETRANSFERBNB VALUE", value);
        (bool success, ) = to.call{value: value}("");
        require(success, "TransferHelper: BNB_TRANSFER_FAILED");
    }


    /**
     * @notice Get the claimable stats of specific epoch and user account
     * @param epoch: epoch
     * @param user: user address
     */
    function claimable(uint256 epoch, address user) public view returns (bool) {
        BetInfo memory betInfo = ledger[epoch][user];
        Round memory round = rounds[epoch];
        return
            round.oracleCalled &&
            betInfo.amount != 0 &&
            !betInfo.claimed &&
            ((round.winningPlayer > 0 && betInfo.position == Position.Blue) ||
                (round.winningPlayer < 1 && betInfo.position == Position.Red));
    }


    /** Not entirely sure how this is relevant or works?
     * @notice Get the refundable stats of specific epoch and user account
     * @param epoch: epoch
     * @param user: user address
     */
    function refundable(uint256 epoch, address user) public view returns (bool) {
        BetInfo memory betInfo = ledger[epoch][user];
        Round memory round = rounds[epoch];
        return
            !round.oracleCalled &&
            !betInfo.claimed &&
            block.timestamp > round.closeTimestamp &&
            betInfo.amount != 0;
    }

    /**
     * @notice Calculate rewards for round
     * @param epoch: epoch
     */
    function _calculateRewards(uint256 epoch) internal {
        require(rounds[epoch].rewardBaseCalAmount == 0 && rounds[epoch].rewardAmount == 0, "Rewards calculated");
        Round storage round = rounds[epoch];
        uint256 rewardBaseCalAmount;
        uint256 treasuryAmt;
        uint256 rewardAmount;

        // Bull wins (BLUE) 1
        if (round.winningPlayer == 1) {
            rewardBaseCalAmount = round.blueAmount;
            //no winner , house win
            if (rewardBaseCalAmount == 0) {
                treasuryAmt = round.totalAmount;
            } else {
                treasuryAmt = (round.totalAmount * treasuryFee) / 10000;
            }
            rewardAmount = round.totalAmount - treasuryAmt;
        }
        // Bear wins (RED) 0
        else if (round.winningPlayer == 0) {
            rewardBaseCalAmount = round.redAmount;
            //no winner , house win
            if (rewardBaseCalAmount == 0) {
                treasuryAmt = round.totalAmount;
            } else {
                treasuryAmt = (round.totalAmount * treasuryFee) / 10000;
            }
            // console.log("TREASURY AMT?", treasuryAmt);
            // console.log("Round Total Amount: ", round.totalAmount);
            rewardAmount = round.totalAmount - treasuryAmt;
            // console.log("REWARD AMOUNT:", rewardAmount);
        }
        // House wins
        else {
            rewardBaseCalAmount = 0;
            rewardAmount = 0;
            treasuryAmt = round.totalAmount;
        }

        round.rewardBaseCalAmount = rewardBaseCalAmount;
        round.rewardAmount = rewardAmount;

        //console.log("REWARD?", rewardAmount); //1.8 eth reward

        // Add to treasury
        //console.log("TREASURY AMT", treasuryAmt); // works
        //console.log("TRES AMOUNT1:", treasuryAmount);
        treasuryAmount += treasuryAmt;
        //console.log("TRES AMOUNT2:", treasuryAmount);
        //console.log("TREASURY AMOUNT", treasuryAmount);
        //emit RewardsCalculated(epoch, rewardBaseCalAmount, rewardAmount, treasuryAmt);
    }

    function executeRound() public whenNotPaused onlyOwner {
         uint256 currentRoundId = prevRound + 1;
         //console.log("executeRound() current Epoch: ", curEpoch);
        // dont calc rewards of round that doesnt exist (ex. epoch = 0 - 1 = -1 OR 1-1 = 0)
         if(curEpoch > 0){
            _calculateRewards(curEpoch); //- 1
         }
         curEpoch = curEpoch + 1;
         _safeStartRound(curEpoch);
    }
    
    function _safeStartRound(uint256 epoch) internal {
        _startRound(epoch);
    }

    function _startRound(uint256 epoch) internal {
        Round storage round = rounds[epoch];
        round.startTimestamp = block.timestamp;
        round.epoch = epoch;
        round.totalAmount = 0;
        emit StartRound(epoch);
    }

    function _safeEndRound(
        uint256 epoch,
        uint256 winner
    ) external onlyOwner {
        require(block.timestamp >= rounds[epoch].startTimestamp, "Can only end round after round started");
        Round storage round = rounds[epoch];
        round.winningPlayer = winner;
        round.oracleCalled = true;
        // add round id?
    }

    ///////////////////////////////////////////////
    // Extra Functions.
    ///////////////////////////////////////////////
    
    // recover tokens sent to contract by mistake
    function recoverToken(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice Claim all rewards in treasury
     * @dev Callable by admin
     */
    function claimTreasury() external nonReentrant onlyOwner {
        uint256 currentTreasuryAmount = treasuryAmount;
        treasuryAmount = 0;
        console.log("currentTreasuryAmount: ", currentTreasuryAmount);
        _safeTransferBNB(adminAddress, currentTreasuryAmount);

        //emit TreasuryClaim(currentTreasuryAmount);
    }

}
