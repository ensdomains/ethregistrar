pragma solidity ^0.4.20;

import "@ensdomains/ens/contracts/ENS.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract BaseRegistrar is Ownable {
    uint constant GRACE_PERIOD = 30 days;

    struct Registration {
        address owner;
        uint expiresAt; // Expiration timestamp
    }

    event NameRegistered(bytes32 indexed hash, address indexed owner, uint expires);
    event NameRenewed(bytes32 indexed hash, uint expires);
    event NameTransferred(bytes32 indexed hash, address indexed oldOwner, address indexed newOwner);

    mapping(bytes32=>Registration) public registrations;
    uint public deployedAt;
    ENS public ens;
    bytes32 public baseNode;

    constructor(ENS _ens, bytes32 _baseNode) public {
        ens = _ens;
        baseNode = _baseNode;
        deployedAt = now;
    }

    modifier isRegistrar {
        require(ens.owner(baseNode) == address(this));
        _;
    }

    modifier owns(bytes32 hash) {
        require(registrations[hash].owner == msg.sender);
        require(registrations[hash].expiresAt > now);
        _;
    }

    /**
     * @dev Returns the current rent price, in wei per second.
     */
    function rentPrice(bytes32 hash, uint duration) view public returns(uint) {
        return 0;
    }

    function available(bytes32 hash) public constant returns(bool) {
        return registrations[hash].expiresAt + GRACE_PERIOD < now;
    }

    /**
     * @dev Register or renew a name.
     */
    function register(bytes32 hash, address owner, uint duration) public payable isRegistrar {
        require(available(hash));

        uint cost = rentPrice(hash, duration);
        require(cost <= msg.value);

        // Transfer back excess funds
        if(cost < msg.value) {
            msg.sender.transfer(msg.value - cost);
        }

        doRegister(hash, owner, duration);
        ens.setSubnodeOwner(baseNode, hash, owner);
    }

    function renew(bytes32 hash, uint duration) public payable owns(hash) isRegistrar {
        uint cost = rentPrice(hash, duration);
        require(cost <= msg.value);

        if(cost < msg.value) {
            msg.sender.transfer(msg.value - cost);
        }

        registrations[hash].expiresAt += duration;
        emit NameRenewed(hash, now + duration);
    }

    function doRegister(bytes32 hash, address owner, uint duration) internal {
        registrations[hash] = Registration(owner, now + duration);
        emit NameRegistered(hash, owner, now + duration);
    }

    /**
     * @dev Transfer ownership of a name to another account.
     */
    function transfer(bytes32 hash, address newOwner) public owns(hash) {
        emit NameTransferred(hash, registrations[hash].owner, newOwner);
        registrations[hash].owner = newOwner;
    }

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(bytes32 hash) public owns(hash) isRegistrar {
        ens.setSubnodeOwner(baseNode, hash, registrations[hash].owner);
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }
}
