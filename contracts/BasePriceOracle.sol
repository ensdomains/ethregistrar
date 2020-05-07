pragma solidity >=0.5.0;

import "./PriceOracle.sol";
import "./BaseRegistrar.sol";
import "./SafeMath.sol";
import "./StringUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";


contract BasePriceOracle is Ownable, PriceOracle {
    using SafeMath for uint;
    using StringUtils for string;

    // Rent in base price units by length. Element 0 is for 1-length names, and so on.
    uint[] public rentPrices;
    BaseRegistrar public registrar;

    event RentPriceChanged(uint[] prices);

    constructor(uint[] memory _rentPrices, address _registrar) public {
        registrar = BaseRegistrar(_registrar);
        setPrices(_rentPrices);
    }

    function price(string calldata name, uint expires, uint duration) external view returns(uint) {
        uint len = name.strlen();
        if(len > rentPrices.length) {
            len = rentPrices.length;
        }
        require(len > 0);
        uint basePrice = rentPrices[len - 1].mul(duration);

        return basePriceToWei(basePrice);
    }

    /**
     * @dev Sets rent prices.
     * @param _rentPrices The price array. Each element corresponds to a specific
     *                    name length; names longer than the length of the array
     *                    default to the price of the last element.
     */
    function setPrices(uint[] memory _rentPrices) public onlyOwner {
        rentPrices = _rentPrices;
        emit RentPriceChanged(_rentPrices);
    }

    /**
     * @dev Converts from base price units to wei.
     *      Base price units are arbitrary values used for internal computation.
     * @param basePrice The base price to convert from.
     * @return The price in wei.
     */
    function basePriceToWei(uint basePrice) internal view returns(uint);
}