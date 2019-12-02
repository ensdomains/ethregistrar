pragma solidity ^0.5.0;

import "./PriceOracle.sol";
import "./SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract SimplePriceOracle is Ownable, PriceOracle {
    using SafeMath for *;

    // Rent in wei per second
    uint public rentPrice;

    event RentPriceChanged(uint price);

    constructor(uint _rentPrice) public {
        setPrice(_rentPrice);
    }

    function setPrice(uint _rentPrice) public onlyOwner {
        rentPrice = _rentPrice;
        emit RentPriceChanged(_rentPrice);
    }

    /**
     * @dev Returns the price to register or renew a name.
     * @param duration How long the name is being registered or extended for, in seconds.
     * @return The price of this renewal or registration, in wei.
     */
    function price(string calldata /*name*/, uint /*expires*/, uint duration) external view returns(uint) {
        return duration.mul(rentPrice);
    }
}
