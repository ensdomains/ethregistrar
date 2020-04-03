pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract ACL is Ownable {
    event ACLChanged(address indexed addr, bool access);

    mapping(address=>bool) public entries;

    function setAccess(address addr, bool access) public onlyOwner {
        entries[addr] = access;
        emit ACLChanged(addr, access);
    }
}
