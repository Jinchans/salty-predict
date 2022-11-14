// SPDX-License-Identifier: MIT




pragma solidity ^0.8.7;

// REMIX IMPORTS
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

// LOCAL IMPORTS
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol"; // delete in production

contract SaltyPredict is Ownable, Pausable, ReentrancyGuard {
   using SafeERC20 for IERC20;


   uint256 public minBetAmount;
   uint256 public curEpoch;
   uint256 public prevRound;
   uint256 public curRound;
   address public adminAddress; 
   uint256 public treasuryAmount;
   uint256 public treasuryFee;
   uint256 public publicUnpause; // signature to unpause game

   mapping(uint256 => mapping(address => BetInfo)) public ledger;
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
    event SafeEndRound(uint256 winner);

    constructor(){
        adminAddress = msg.sender;
        treasuryFee = 1000; // 10%
        minBetAmount = 1 ether;
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

        for (uint256 i = 0; i < epochs.length; i++) {
           
            require(rounds[epochs[i]].startTimestamp != 0, "Round has not started");
            require(block.timestamp > rounds[epochs[i]].closeTimestamp, "Round has not ended");
            uint256 addedReward = 0;
            
            if (rounds[epochs[i]].oracleCalled) {
                
                require(claimable(epochs[i], msg.sender), "Not eligible for claim");
                Round memory round = rounds[epochs[i]];

                if(round.rewardBaseCalAmount != 0){
                addedReward = (ledger[epochs[i]][msg.sender].amount * round.rewardAmount) / round.rewardBaseCalAmount;
                }
            }
            else {
                require(refundable(epochs[i], msg.sender), "Not eligible for refund");
                addedReward = ledger[epochs[i]][msg.sender].amount;
            }

            ledger[epochs[i]][msg.sender].claimed = true;
            reward += addedReward;

            emit Claim(msg.sender, epochs[i], addedReward);
        }
        if (reward > 0) {
            _safeTransferBNB(address(msg.sender), reward);
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
            rewardAmount = round.totalAmount - treasuryAmt;
        }
        // House wins
        else {
            rewardBaseCalAmount = 0;
            rewardAmount = 0;
            treasuryAmt = round.totalAmount;
        }

        round.rewardBaseCalAmount = rewardBaseCalAmount;
        round.rewardAmount = rewardAmount;
        treasuryAmount += treasuryAmt;
    }

    function executeRound() public whenNotPaused onlyOwner {
        
        if(curRound != 0){
         require(curRound == prevRound, "prev round has not yet ended!");
        }

         curRound = prevRound + 1;
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
        // add end timestamp?
    ) external onlyOwner {
        require(curRound > prevRound, "prev round has not yet ended!");
        require(block.timestamp >= rounds[epoch].startTimestamp, "Can only end round after round started");
        Round storage round = rounds[epoch];
        round.winningPlayer = winner;
        round.oracleCalled = true;
        prevRound ++;
        emit SafeEndRound(winner);
    }

       /**
     * @notice Returns round epochs and bet information for a user that has participated
     * @param user: user address
     * @param cursor: cursor
     * @param size: size
     */
    function getUserRounds(
        address user,
        uint256 cursor,
        uint256 size
    )
        external
        view
        returns (
            uint256[] memory,
            BetInfo[] memory,
            uint256
        )
    {
        uint256 length = size;

        if (length > userRounds[user].length - cursor) {
            length = userRounds[user].length - cursor;
        }

        uint256[] memory values = new uint256[](length);
        BetInfo[] memory betInfo = new BetInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            values[i] = userRounds[user][cursor + i];
            betInfo[i] = ledger[values[i]][user];
        }

        return (values, betInfo, cursor + length);
    }

    /**
     * @notice Returns round epochs length
     * @param user: user address
     */
    function getUserRoundsLength(address user) external view returns (uint256) {
        console.log("test? inside user rounds?");
        return userRounds[user].length;
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
    }

    /**
     * @notice Owner Pause Game
     * @dev Callable by admin
     */
    function pause() external whenNotPaused onlyOwner {
        require(curEpoch == prevRound); // prevent overlap, can only pause before initilization of new round
        _pause();
        publicUnpause = 0;
    }

    function playerSignature() public whenPaused {
        publicUnpause++;
    }

    function confirmUnpause() external whenPaused {
        require(publicUnpause >= 1, "require at least 1 person to sign");
        _unpause();
    }

    function _unpause() internal override whenPaused {
        _unpause();
    }

}
