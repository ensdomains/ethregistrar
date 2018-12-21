pragma solidity ^0.4.20;

import "./PriceOracle.sol";
import "./BaseRegistrar.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract ETHRegistrarController is Ownable {
    BaseRegistrar base;
    PriceOracle prices;

    event NameRegistered(string name, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(BaseRegistrar _base, PriceOracle _prices) public {
        base = _base;
        prices = _prices;
    }

    function rentPrice(string name, uint duration) view public returns(uint) {
        bytes32 hash = keccak256(name);
        return prices.price(name, base.nameExpires(hash), duration);
    }

    function available(string name) public view returns(bool) {
        return strlen(name) > 6 && base.available(keccak256(name));
    }

    function register(string name, address owner, uint duration) external payable {
        uint cost = rentPrice(name, duration);

        require(available(name));
        require(msg.value >= cost);

        uint expires = base.register(keccak256(name), owner, duration);

        if(msg.value > cost) {
            msg.sender.transfer(cost - msg.value);
        }

        emit NameRegistered(name, owner, cost, expires);
    }

    function renew(string name, uint duration) external payable {
        uint cost = rentPrice(name, duration);
        require(msg.value >= cost);

        uint expires = base.renew(keccak256(name), duration);

        if(msg.value > cost) {
            msg.sender.transfer(cost - msg.value);
        }

        emit NameRenewed(name, cost, expires);
    }

    function setPriceOracle(PriceOracle _prices) onlyOwner {
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }

    function withdraw() onlyOwner {
        msg.sender.transfer(this.balance);
    }

    /**
     * @dev Returns the length of a given string
     *
     * @param s The string to measure the length of
     * @return The length of the input string
     */
    function strlen(string s) internal pure returns (uint) {
        s; // Don't warn about unused variables
        // Starting here means the LSB will be the byte we care about
        uint ptr;
        uint end;
        assembly {
            ptr := add(s, 1)
            end := add(mload(s), ptr)
        }
        for (uint len = 0; ptr < end; len++) {
            uint8 b;
            assembly { b := and(mload(ptr), 0xFF) }
            if (b < 0x80) {
                ptr += 1;
            } else if (b < 0xE0) {
                ptr += 2;
            } else if (b < 0xF0) {
                ptr += 3;
            } else if (b < 0xF8) {
                ptr += 4;
            } else if (b < 0xFC) {
                ptr += 5;
            } else {
                ptr += 6;
            }
        }
        return len;
    }
}
