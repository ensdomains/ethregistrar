pragma solidity ^0.4.24;

import "./PriceOracle.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract SimplePriceOracle is Ownable, PriceOracle {
    // Rent in wei per second
    uint public rentPrice;

    event RentPriceChanged(uint price);

    constructor(uint _rentPrice) {
        setPrice(_rentPrice);
    }

    function setPrice(uint _rentPrice) onlyOwner {
        rentPrice = _rentPrice;
        emit RentPriceChanged(_rentPrice);
    }

    /**
     * @dev Returns the price to register or renew a name.
     * @param name The name being registered or renewed.
     * @param expires When the name presently expires (0 if this is a new registration).
     * @param duration How long the name is being registered or extended for, in seconds.
     * @return The price of this renewal or registration, in wei.
     */
    function price(string name, uint expires, uint duration) view public returns(uint) {
        return duration * rentPrice;
    }
}
