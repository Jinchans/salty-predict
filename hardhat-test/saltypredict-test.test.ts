import { assert, expect } from 'chai';
import { ethers } from 'hardhat';
import { constants, Contract, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { mine } from "@nomicfoundation/hardhat-network-helpers";

const { parseEther } = utils;

describe('Test Smart Contract: ', function () {

    // Addresses
    let deployer: SignerWithAddress; // owner
    let alice: SignerWithAddress;
    let bob: SignerWithAddress;
    let carl: SignerWithAddress;

    // Variables
    let _saltyPredict: Contract;
    let epoch = 0;

    before(async function () {
        [deployer, alice, bob, carl] = await ethers.getSigners();
        const SaltyPredict = await ethers.getContractFactory('SaltyPredict');
        _saltyPredict = await SaltyPredict.deploy();
        const tx = await _saltyPredict.deployed();
    });


    // 1. make sure pause is false
    it('1: test pause', async () => {
        expect(await _saltyPredict.paused()).to.equal(false);
    });


    // 2. EXECUTE FIRST ROUND
    it('2: execute/start round 1', async () => {
        const tx = await _saltyPredict.connect(deployer).executeRound();
    });

   
    // 3. ALICE BETS RED "0"
    it('3: alice bets red', async () => {
        const balance_alice1 = await ethers.provider.getBalance('0x70997970C51812dc3A010C7d01b50e0d17dc79C8');
        console.log("ALICE BALANCE BEFORE BET: ", balance_alice1.toString());

        const epoch = 1;
        const tx = await _saltyPredict.connect(alice).betRed(epoch, {value: ethers.utils.parseEther("1.0")});

        const balance_alice2 = await ethers.provider.getBalance('0x70997970C51812dc3A010C7d01b50e0d17dc79C8');
        console.log("ALICE BALANCE AFTER BET: ", balance_alice2.toString());
    });


    // 4. BOB BETS BLUE "1"
    it('4: bob bets blue', async () => {

        const balance_bob1 = await ethers.provider.getBalance('0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC');
        console.log("BOB BALANCE BEFORE BET: ", balance_bob1.toString());

        const epoch = 1;
        const tx = await _saltyPredict.connect(bob).betBlue(1, {value: ethers.utils.parseEther("1.0")});

        const balance_bob2 = await ethers.provider.getBalance('0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC');
        console.log("BOB BALANCE AFTER BET: ", balance_bob2.toString());
    });

    /* 45s limit working good.
    // Cannot bet after 45 seconds have passed WTF? hardhat testing is fucked.
    it('5: Cannot bet after 45 sec', async () => {
        await mine(50);
        const blockTimestampNew = await ethers.provider.getBlockNumber();
        expect(await _saltyPredict.connect(carl).betRed(1, {value: ethers.utils.parseEther("1.0")})).to.be.revertedWith('Round Not Bettable');
    })
    */

    // 5. Declare Winner Round 1
    it('5: declare winner and end round 1', async() => {
        const tx = await _saltyPredict.connect(deployer)._safeEndRound(1,0); // round 1, winner is red 0
    })

    // 6. Execute Round 2
    it('6: execute/start round 2', async () => {
        const tx = await _saltyPredict.connect(deployer).executeRound();
        const blockTimestamp = await ethers.provider.getBlockNumber();
    });

    // 7. ALICE BETS BLUE Round 2
    it('7: alice bets red round 2', async () => {
        const tx = await _saltyPredict.connect(alice).betBlue(2, {value: ethers.utils.parseEther("1.0")});
    });

    // 8. BOB BETS BLUE Round 2
    it('8: bob bets blue round 2', async () => {
        const tx = await _saltyPredict.connect(bob).betBlue(2, {value: ethers.utils.parseEther("1.0")});
    });


    // 9. Red 0 Wins Again 2x
    it('9: declare red winner and end round', async() => {
        const tx = await _saltyPredict.connect(deployer)._safeEndRound(2,0);
    });

    // 10. Execute Round 3
    it('10: execute/start round 3', async () => {
        const tx = await _saltyPredict.connect(deployer).executeRound();
        const blockTimestamp = await ethers.provider.getBlockNumber();
    });

    // 11. Alice bets red round 3
    it('11: alice bets red round 3', async () => {
        const tx = await _saltyPredict.connect(alice).betRed(3, {value: ethers.utils.parseEther("1.0")});
        //expect(tx).to.emit(BetRed);
    });

    // 12. Bob bets blue round 3
    it('12: bob bets blue round 3', async () => {
        const tx = await _saltyPredict.connect(bob).betBlue(3, {value: ethers.utils.parseEther("1.0")});
        // expect tx to emit Bet Blue
    });

    // 13. Red wins round 3
    it('13: declare winner and end round', async() => {
        const tx = await _saltyPredict.connect(deployer)._safeEndRound(3,0);
    });


    // 14. Test claim rewards alice wins all 3 matches (0.8 x 3 = 2.4 eth)?
    it('14: test claim round 1 alice', async() => {
        const epochs = [1]; // epoch 2 claim.. adding a array gives error?
        const tx = await _saltyPredict.connect(alice).claim(epochs);

        console.log("CLAIM: ", tx.toString());
    });

    // 15. Check and compare balances of Bob vs Alice. Expect alice to have a higher balance
    it('15: test balances', async() => {
        const balanceBob = await ethers.provider.getBalance("0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC");
        const balanceAlice = await ethers.provider.getBalance("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");
        console.log("BALANCE A:", balanceAlice.toString()); // Alice 3 wins = 10,001.6 Eth
        console.log("BALANCE B:", balanceBob.toString()); // Bob 3 loss = 9,997.9

        // conclusion: Alice > Bob
        // Math Check Alice: 1 + 1 + 0.001 = 2.001 Eth bet. 10,000 = 9,997.999 ETH -> + 1.8 + 1.8 (3.6) -> 10,001.599 (0.2 goes to treasury = 0.4 total)
    });


    // 16. Get user bets length
    it('16: test user bets length', async() => {
        const lengthBob = await _saltyPredict.connect(bob).getUserRoundsLength("0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC");
        const lengthAlice = await _saltyPredict.connect(alice).getUserRoundsLength("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");

        console.log("LENGTH BOB:", lengthBob.toString());
        console.log("LENGTH ALICE:", lengthAlice.toString());

        // conclusion: 3 for both
    })


    // 17. Get all users played rounds
    it('17: test all user played rounds', async() => {
        const allRoundsBob = await _saltyPredict.connect(bob).getUserRounds("0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", "0", "10");
        const allRoundsAlice = await _saltyPredict.connect(alice).getUserRounds("0x70997970C51812dc3A010C7d01b50e0d17dc79C8", "0", "10");

        console.log("ALL ROUNDS BOB", allRoundsBob.toString());
        console.log("ALL ROUNDS ALICE", allRoundsAlice.toString());
    })

    // 16. claim treasury deployer
    it('16: Claim Treasury', async() => {
        const claimTx = await _saltyPredict.connect(deployer).claimTreasury();
    });
    

    // getUserLength() => getUserRounds => List out claimable rounds => Seperate Already claimed / Unclaimed => Claim()

    // 9. Get total bets, prev round data, ledger data etc.
    /* 
    it('9: check the ledger and verify data', async () => {
        const tx1 = await _saltyPredict.ledger(2, '0x70997970C51812dc3A010C7d01b50e0d17dc79C8'); // epoch and address alice
        console.log('Ledger data Alice Epoch 0: ', tx1);

        const tx2 = await _saltyPredict.ledger(2, '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC'); // epoch and address alice
        console.log('Ledger data Bob Epoch 0: ', tx2);
        
    });
    */

    // not eligible for claim - working good!
    /* 
    it('5.5: test non winning claim expect error', async() => {
        const epochs = [1];
        const tx = await _saltyPredict.connect(bob).claim(epochs);
        // expect revert with uneligible for claim - good
    })
    */

    // it('6: test claim', async() => {
    //     const epochs = [2];
    //     const tx = await _saltyPredict.connect(bob).claim(epochs);
    //     console.log("Claim result?", tx)
    // });


});
