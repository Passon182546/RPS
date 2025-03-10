// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "./TimeUnit.sol";
import "./CommitReveal.sol";

contract RPSGame {
    uint public playerCount = 0;  // จำนวนผู้เล่นที่เข้าร่วมเกม
    uint public prizePool = 0;    // จำนวนเงินรางวัลรวม
    mapping(address => bytes32) public playerHashes;  // เก็บค่า hash ที่ผู้เล่นส่งมา
    mapping(address => uint) public playerChoices;  // เก็บการเลือกของผู้เล่น
    address[] public activePlayers;  // เก็บที่อยู่ของผู้เล่นที่กำลังเล่นอยู่
    uint public inputCount = 0;  // จำนวนการเลือกที่ได้รับจากผู้เล่น
    uint256 public gameStartTimestamp;  // เวลาที่เกมเริ่ม
    uint256 public gameDuration = 6 minutes;  // ระยะเวลาเกม

    TimeUnit public timeModule;  // ใช้โมดูลเวลา
    CommitReveal public commitRevealModule;  // ใช้โมดูล commit-reveal

    // คอนสตรัคเตอร์: กำหนดที่อยู่ของ TimeUnit และ CommitReveal contract
    constructor(address _timeUnitAddress, address _commitRevealAddress) {
        timeModule = TimeUnit(_timeUnitAddress);
        commitRevealModule = CommitReveal(_commitRevealAddress);
    }

    // รายชื่อผู้เล่นที่ได้รับอนุญาตให้เล่นในเกม
    address[4] private allowedPlayers = [
        0x5B38Da6a701c568545dCfcB03FcB875f56beddC4,
        0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,
        0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db,
        0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB
    ];

    // Modifier: ตรวจสอบว่า caller เป็นผู้เล่นที่ได้รับอนุญาต
    modifier onlyAuthorizedPlayers() {
        bool isAuthorized = false;
        for (uint i = 0; i < allowedPlayers.length; i++) {
            if (msg.sender == allowedPlayers[i]) {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "You are not authorized to play");
        _;
    }

    // ฟังก์ชันให้ผู้เล่นเข้าร่วมเกมโดยการส่ง 1 ETH
    function joinGame() public payable onlyAuthorizedPlayers {
        require(playerCount < 2, "Game is already full");  // เกมเต็มแล้ว
        require(msg.value == 1 ether, "Must send exactly 1 ETH");  // ต้องส่ง 1 ETH เท่านั้น
        require(activePlayers.length == 0 || msg.sender != activePlayers[0], "Player already joined");  // ตรวจสอบว่าไม่ใช่ผู้เล่นคนเดียวกันที่เข้าร่วม

        if (playerCount == 0) {
            gameStartTimestamp = block.timestamp;  // กำหนดเวลาเริ่มเกมเมื่อผู้เล่นคนแรกเข้ามา
        }

        prizePool += msg.value;  // เพิ่มเงินรางวัลรวม
        activePlayers.push(msg.sender);  // เพิ่มผู้เล่นในรายการ
        playerCount++;  // เพิ่มจำนวนผู้เล่น
    }

    // ฟังก์ชันให้ผู้เล่นทำการ commit การเลือกโดยใช้ hash
    function commitPlayerChoice(bytes32 hashChoice) public onlyAuthorizedPlayers {
        require(playerCount == 2, "Game has not started yet");  // เกมยังไม่เริ่ม
        require(playerHashes[msg.sender] == 0, "Choice already committed");  // ตรวจสอบว่าผู้เล่นยังไม่ได้ commit การเลือก
        commitRevealModule.commit(hashChoice);  // เรียก commit ในโมดูล CommitReveal
        playerHashes[msg.sender] = hashChoice;  // เก็บ hash การเลือก
    }

    // ฟังก์ชันให้ผู้เล่นเปิดเผยการเลือกและตรวจสอบความถูกต้องของ commit
    function revealPlayerChoice(uint choice, uint nonce) public onlyAuthorizedPlayers {
        require(playerCount == 2, "Game has not started yet");  // เกมยังไม่เริ่ม
        require(playerHashes[msg.sender] != 0, "No choice committed");  // ผู้เล่นยังไม่ได้ commit การเลือก
        require(choice >= 0 && choice <= 4, "Invalid choice");  // ตรวจสอบว่าเลือกตัวเลือกที่ถูกต้อง
        require(commitRevealModule.getHash(keccak256(abi.encodePacked(choice, nonce))) == playerHashes[msg.sender], "Reveal does not match commitment");  // ตรวจสอบว่า reveal ตรงกับการ commit

        playerChoices[msg.sender] = choice;  // เก็บการเลือกของผู้เล่น
        inputCount++;  // เพิ่มจำนวนการเลือกที่ได้รับ

        if (inputCount == 2) {
            determineWinnerAndReward();  // ถ้าผู้เล่นทั้งสองเลือกแล้ว ให้ตัดสินผู้ชนะ
        }
    }

    // ฟังก์ชันให้ผู้เล่นถอนเงินรางวัลเมื่อเกมหมดเวลา
    function withdrawIfGameTimedOut() public {
        require(block.timestamp >= gameStartTimestamp + gameDuration, "Game has not timed out yet");  // ตรวจสอบว่าเกมหมดเวลาแล้ว

        if (playerCount == 1) {
            payable(activePlayers[0]).transfer(prizePool);  
        } else if (playerCount == 2) {
            payable(activePlayers[0]).transfer(prizePool / 2);  
            payable(activePlayers[1]).transfer(prizePool / 2);  
        }
        resetGame();  // รีเซ็ตสถานะของเกม
    }

    // ฟังก์ชันสำหรับตัดสินผู้ชนะและแจกเงินรางวัล
    function determineWinnerAndReward() private {
        uint player1Choice = playerChoices[activePlayers[0]];  // การเลือกของผู้เล่นคนแรก
        uint player2Choice = playerChoices[activePlayers[1]];  // การเลือกของผู้เล่นคนที่สอง
        address payable player1 = payable(activePlayers[0]);
        address payable player2 = payable(activePlayers[1]);

        // กฎการชนะเกม (Rock-Paper-Scissors-Lizard-Spock)
        if ((player1Choice + 1) % 5 == player2Choice || (player1Choice + 3) % 5 == player2Choice) {
            player2.transfer(prizePool);  // ผู้เล่นสองชนะ
        } else if ((player2Choice + 1) % 5 == player1Choice || (player2Choice + 3) % 5 == player1Choice) {
            player1.transfer(prizePool);  // ผู้เล่นหนึ่งชนะ
        } else {
            player1.transfer(prizePool / 2);  // เสมอ แบ่งรางวัลครึ่งหนึ่งให้ทั้งสอง
            player2.transfer(prizePool / 2);
        }
        resetGame();  // รีเซ็ตเกมหลังจากตัดสินผล
    }

   function resetGame() private {
    prizePool = 0;
    playerCount = 0;
    inputCount = 0;
    
    // ลบค่าของ playerHashes และ playerChoices สำหรับผู้เล่นที่อยู่ใน activePlayers
    if (activePlayers.length > 0) {
        delete playerHashes[activePlayers[0]];
    }
    if (activePlayers.length > 1) {
        delete playerHashes[activePlayers[1]];
    }
    
    if (activePlayers.length > 0) {
        delete playerChoices[activePlayers[0]];
    }
    if (activePlayers.length > 1) {
        delete playerChoices[activePlayers[1]];
    }

    // รีเซ็ต array ของ activePlayers เป็น array ว่าง
    delete activePlayers;  // ใช้ delete เพื่อรีเซ็ต array

    // รีเซ็ต gameStartTimestamp เป็น 0 โดยใช้ delete
    delete gameStartTimestamp;
}

    // ฟังก์ชันคำนวณ commit hash จากการเลือกและ nonce
    function computeCommitmentHash(uint choice, uint nonce) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(choice, nonce));  // คืนค่าผลลัพธ์เป็น hash
    }
}
