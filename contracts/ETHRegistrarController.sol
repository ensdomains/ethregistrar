pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "./ACL.sol";
import "./PriceOracle.sol";
import "./BaseRegistrar.sol";
import "./StringUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "@ensdomains/resolver/contracts/Resolver.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract ETHRegistrarController is Ownable {
    using StringUtils for *;
    using SafeMath for uint256;

    uint constant public MIN_REGISTRATION_DURATION = 28 days;

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private COMMITMENT_CONTROLLER_ID = bytes4(
        keccak256("rentPrice(string,uint256)") ^
        keccak256("available(string)") ^
        keccak256("makeCommitment(string,address,bytes32)") ^
        keccak256("commit(bytes32)") ^
        keccak256("register(string,address,uint256,bytes32)") ^
        keccak256("renew(string,uint256)")
    );
    bytes4 constant private COMMITMENT_WITH_CONFIG_CONTROLLER_ID = bytes4(
        keccak256("registerWithConfig(string,address,uint256,bytes32,address,address)") ^
        keccak256("makeCommitmentWithConfig(string,address,bytes32,address,address)")
    );
    bytes4 constant public BULK_RENEWAL_ID = bytes4(
        keccak256("rentPrice(string[],uint)") ^
        keccak256("renewAll(string[],uint")
    );

    // Base Registrar contract
    BaseRegistrar public base;
    // Price oracle contract
    PriceOracle public prices;
    // Minimum and maximum commitment ages, in seconds.
    uint public minCommitmentAge;
    uint public maxCommitmentAge;
    // Referral fee, in 1/1000ths
    uint public referralFeeMillis = 0;
    // A map of commitment values to when they were committed to
    mapping(bytes32=>uint) public commitments;
    // An access-control list for referrers
    ACL public referrers;

    event NameRegistered(string name, bytes32 indexed label, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);
    event ReferralFeeSent(address indexed referrer, uint amount);
    event NewPriceOracle(address indexed oracle);

    constructor(BaseRegistrar _base, PriceOracle _prices, uint _minCommitmentAge, uint _maxCommitmentAge, ACL _referrers) public {
        base = _base;
        prices = _prices;
        setCommitmentAges(_minCommitmentAge, _maxCommitmentAge);
        setReferrersACL(_referrers);
    }

    function rentPrice(string memory name, uint duration) view public returns(uint) {
        bytes32 hash = keccak256(bytes(name));
        return prices.price(name, base.nameExpires(uint256(hash)), duration);
    }

    function valid(string memory name) public pure returns(bool) {
        return name.strlen() >= 3;
    }

    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function makeCommitment(string memory name, address owner, bytes32 secret) pure public returns(bytes32) {
        return makeCommitmentWithConfig(name, owner, secret, address(0), address(0));
    }

    function makeCommitmentWithConfig(string memory name, address owner, bytes32 secret, address resolver, address addr) pure public returns(bytes32) {
        bytes32 label = keccak256(bytes(name));
        if (resolver == address(0) && addr == address(0)) {
            return keccak256(abi.encodePacked(label, owner, secret));
        }
        require(resolver != address(0));
        return keccak256(abi.encodePacked(label, owner, resolver, addr, secret));
    }

    function commit(bytes32 commitment) public {
        require(commitments[commitment] + maxCommitmentAge < now);
        commitments[commitment] = now;
    }

    function register(string calldata name, address owner, uint duration, bytes32 secret) external payable {
        registerWithReferrer(name, owner, duration, secret, address(0), address(0), address(0));
    }

    function registerWithConfig(string memory name, address owner, uint duration, bytes32 secret, address resolver, address addr) public payable {
        registerWithReferrer(name, owner, duration, secret, address(0), resolver, addr);
    }

    function registerWithReferrer(string memory name, address owner, uint duration, bytes32 secret, address payable referrer, address resolver, address addr) public payable {
        bytes32 commitment = makeCommitmentWithConfig(name, owner, secret, resolver, addr);
        uint cost = _consumeCommitment(name, duration, commitment);

        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);

        uint expires;
        if(resolver != address(0)) {
            // Set this contract as the (temporary) owner, giving it
            // permission to set up the resolver.
            expires = base.register(tokenId, address(this), duration);

            // The nodehash of this label
            bytes32 nodehash = keccak256(abi.encodePacked(base.baseNode(), label));

            // Set the resolver
            base.ens().setResolver(nodehash, resolver);

            // Configure the resolver
            if (addr != address(0)) {
                Resolver(resolver).setAddr(nodehash, addr);
            }

            // Now transfer full ownership to the expeceted owner
            base.reclaim(tokenId, owner);
            base.transferFrom(address(this), owner, tokenId);
        } else {
            require(addr == address(0));
            expires = base.register(tokenId, owner, duration);
        }

        emit NameRegistered(name, label, owner, cost, expires);

        // Refund any extra payment
        if(msg.value > cost) {
            msg.sender.transfer(msg.value - cost);
        }

        _sendReferralFee(referrer, cost);
    }

    function renew(string calldata name, uint duration) external payable {
        renewWithReferrer(name, duration, address(0));
    }

    function renewWithReferrer(string memory name, uint duration, address payable referrer) public payable {
        uint cost = _doRenew(name, duration);
        require(msg.value >= cost);

        // Refund any extra
        if(msg.value > cost) {
            msg.sender.transfer(msg.value - cost);
        }

        _sendReferralFee(referrer, cost);
    }
    function renewAll(string[] calldata names, uint duration, address payable referrer) external payable {
        uint totalCost = 0;
        for(uint i = 0; i < names.length; i++) {
            totalCost += _doRenew(names[i], duration);
        }
        require(totalCost <= msg.value);

        // Refund any extra
        if(totalCost < msg.value) {
            msg.sender.transfer(msg.value - totalCost);
        }

        _sendReferralFee(referrer, totalCost);
    }

    function setPriceOracle(PriceOracle _prices) public onlyOwner {
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }

    function setCommitmentAges(uint _minCommitmentAge, uint _maxCommitmentAge) public onlyOwner {
        require(_minCommitmentAge < _maxCommitmentAge);
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function setReferralFee(uint _referralFeeMillis) public onlyOwner {
        require(_referralFeeMillis < 1000);
        referralFeeMillis = _referralFeeMillis;
    }

    function setReferrersACL(ACL _referrers) public onlyOwner {
        referrers = _referrers;
    }

    function withdraw() public onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == COMMITMENT_CONTROLLER_ID ||
               interfaceID == COMMITMENT_WITH_CONFIG_CONTROLLER_ID ||
               interfaceID == BULK_RENEWAL_ID;
    }

    function _consumeCommitment(string memory name, uint duration, bytes32 commitment) internal returns (uint256) {
        // Require a valid commitment
        require(commitments[commitment] + minCommitmentAge <= now);

        // If the commitment is too old, or the name is registered, stop
        require(commitments[commitment] + maxCommitmentAge > now);
        require(available(name));

        delete(commitments[commitment]);

        uint cost = rentPrice(name, duration);
        require(duration >= MIN_REGISTRATION_DURATION);
        require(msg.value >= cost);

        return cost;
    }

    function _doRenew(string memory name, uint duration) internal returns(uint cost) {
        uint cost = rentPrice(name, duration);
        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);
        emit NameRenewed(name, label, cost, expires);
        return cost;
    }
    
    function _sendReferralFee(address payable referrer, uint cost) internal {
        if(referrer != address(0) && referralFeeMillis > 0 && address(referrers) != address(0)) {
            require(referrers.entries(referrer));
            uint referralFee = (cost * referralFeeMillis) / 1000;
            referrer.transfer(referralFee);
            emit ReferralFeeSent(referrer, referralFee);
        }
    }
}
