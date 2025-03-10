// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

contract CommitReveal {
    // Struct สำหรับเก็บข้อมูล Commit ของแต่ละผู้เล่น
    struct Commit {
        bytes32 commit;
        uint64 blockNumber;
        bool revealed;
    }

    // Commit เป็น struct ที่เก็บข้อมูลของการ Commit ของแต่ละผู้เล่น
    mapping(address => Commit) public commits;

    // Event สำหรับแจ้งเตือนเมื่อมีการ Commit และ Reveal
    event CommitHash(address indexed sender, bytes32 commitHash);
    event RevealHash(address indexed sender, bytes32 revealHash);

    // ฟังก์ชันสำหรับบันทึกค่า Commit Hash ของผู้ใช้
    function commit(bytes32 commitHash) public {
        require(commits[msg.sender].commit == bytes32(0), "Already committed");
        commits[msg.sender] = Commit(commitHash, uint64(block.number), false);
        emit CommitHash(msg.sender, commitHash);
    }

    // ฟังก์ชันสำหรับเปิดเผยค่า Reveal Hash และตรวจสอบความถูกต้อง
    function reveal(bytes32 revealHash) public {
        require(commits[msg.sender].commit != bytes32(0), "No commit found");
        require(!commits[msg.sender].revealed, "Already revealed");
        require(getHash(revealHash) == commits[msg.sender].commit, "Hash mismatch");

        commits[msg.sender].revealed = true;
        emit RevealHash(msg.sender, revealHash);
    }

    // ฟังก์ชันสำหรับคำนวณค่า Hash ของข้อมูลที่ป้อนเข้าไป
    function getHash(bytes32 data) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(data));
    }
}