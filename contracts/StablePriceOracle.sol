pragma solidity ^0.5.0;

import "./BaseRegistrar.sol";
import "./PriceOracle.sol";
import "./SafeMath.sol";
import "./StringUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

interface DSValue {
    function read() external view returns (bytes32);
}


// StablePriceOracle sets a price in USD, based on an oracle.
contract StablePriceOracle is Ownable, PriceOracle {
    using SafeMath for *;
    using StringUtils for *;

    // Rent in base price units by length. Element 0 is for 1-length names, and so on.
    uint[] public rentPrices;

    BaseRegistrar public registrar;

    // Oracle address
    DSValue public usdOracle;

    event OracleChanged(address oracle);

    event RentPriceChanged(uint[] prices);

    constructor(DSValue _usdOracle, uint[] memory _rentPrices, address _registrar) public {
        usdOracle = _usdOracle;
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

        uint ethPrice = uint(usdOracle.read());
        return basePrice.mul(1e18).div(ethPrice);
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
     * @dev Sets the price oracle address
     * @param _usdOracle The address of the price oracle to use.
     */
    function setOracle(DSValue _usdOracle) public onlyOwner {
        usdOracle = _usdOracle;
        emit OracleChanged(address(_usdOracle));
    }
}
