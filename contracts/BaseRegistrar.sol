pragma solidity ^0.4.20;

import "./PriceOracle.sol";
import "@ensdomains/ens/contracts/ENS.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract BaseRegistrar is Ownable {
    uint constant GRACE_PERIOD = 30 days;

    struct Registration {
        address owner;
        uint expiresAt; // Expiration timestamp
    }

    event NameRegistered(bytes32 indexed hash, string name, address indexed owner, uint expires);
    event NameRenewed(bytes32 indexed hash, string name, uint expires);
    event NameTransferred(bytes32 indexed hash, string name, address indexed oldOwner, address indexed newOwner);

    mapping(bytes32=>Registration) public registrations;
    uint public deployedAt;
    ENS public ens;
    bytes32 public baseNode;
    PriceOracle prices;

    constructor(ENS _ens, bytes32 _baseNode, PriceOracle _prices) public {
        ens = _ens;
        baseNode = _baseNode;
        prices = _prices;
        deployedAt = now;
    }

    modifier isRegistrar {
        require(ens.owner(baseNode) == address(this));
        _;
    }

    modifier owns(string name) {
        bytes32 hash = keccak256(name);
        require(registrations[hash].owner == msg.sender);
        require(registrations[hash].expiresAt > now);
        _;
    }

    function rentPrice(string name, uint duration) view public returns(uint) {
        bytes32 hash = keccak256(name);
        return prices.price(name, registrations[hash].expiresAt, duration);
    }

    function available(string name) public constant returns(bool) {
        return registrations[keccak256(name)].expiresAt + GRACE_PERIOD < now;
    }

    /**
     * @dev Register or renew a name.
     */
    function register(string name, address owner, uint duration) public payable isRegistrar {
        require(available(name));

        uint cost = rentPrice(name, duration);
        require(cost <= msg.value);

        // Transfer back excess funds
        if(cost < msg.value) {
            msg.sender.transfer(msg.value - cost);
        }

        bytes32 hash = keccak256(name);
        doRegister(hash, owner, duration);
        ens.setSubnodeOwner(baseNode, hash, owner);
        emit NameRegistered(hash, name, owner, now + duration);
    }

    function renew(string name, uint duration) public payable isRegistrar {
        bytes32 hash = keccak256(name);
        require(registrations[hash].expiresAt + GRACE_PERIOD >= now);

        uint cost = rentPrice(name, duration);
        require(cost <= msg.value);

        // Transfer back excess funds
        if(cost < msg.value) {
            msg.sender.transfer(msg.value - cost);
        }

        registrations[hash].expiresAt += duration;
        emit NameRenewed(hash, name, now + duration);
    }

    function doRegister(bytes32 hash, address owner, uint duration) internal {
        registrations[hash] = Registration(owner, now + duration);
    }

    /**
     * @dev Transfer ownership of a name to another account.
     */
    function transfer(string name, address newOwner) public owns(name) {
        var hash = keccak256(name);
        emit NameTransferred(hash, name, registrations[hash].owner, newOwner);
        registrations[hash].owner = newOwner;
    }

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(string name) public owns(name) isRegistrar {
        var hash = keccak256(name);
        ens.setSubnodeOwner(baseNode, hash, registrations[hash].owner);
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }
}
