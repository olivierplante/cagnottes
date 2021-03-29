// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.4.25 <0.7.0;

contract Cagnottes {
    
    struct Cagnotte {
        address creator;
        address payable recipient;
        uint256 balance;
        bool paid;
    }
    
    bool private enabled;
    address private owner;
    Cagnotte[] private cagnottes;
    
    modifier ownerOnly() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
    
    modifier enabledOnly() {
        require(enabled, "This contract is disabled");
        _;
    }
    
    constructor() public {
        owner = msg.sender;
        enabled = true;
    }
    
    function createCagnotte(address payable to) public enabledOnly returns (uint256) {
        require(to == address(to),"Invalid address");
        require(to != msg.sender, "Don't be selfish");
        cagnottes.push(Cagnotte(msg.sender, to, 0, false));
        return cagnottes.length - 1;
    }
    
    function contribute(uint id) public payable enabledOnly {
        require(cagnottes.length >= id, "Cagnotte not found");
        Cagnotte storage cagnotte = cagnottes[id];
        require(!cagnotte.paid, "Already paid");
        cagnotte.balance += msg.value;
    }
    
    function collect(uint id) public payable enabledOnly {
        require(cagnottes.length >= id, "Cagnotte not found");
        Cagnotte storage cagnotte = cagnottes[id];
        require(!cagnotte.paid, "Already paid");
        require(cagnotte.creator == msg.sender || cagnotte.recipient == msg.sender, "Only creator or recipient can transfer cagnotte");
        cagnotte.recipient.transfer(cagnotte.balance);
        cagnotte.paid = true;
    }
    
    function toggleEnabled() public ownerOnly {
        enabled = !enabled;
    }
}