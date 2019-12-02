pragma solidity ^0.5.0;

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

    // Oracle address
    DSValue usdOracle;

    // Rent in attodollars (1e-18) per second
    uint[] public rentPrices;

    event OracleChanged(address oracle);
    event RentPriceChanged(uint[] prices);

    constructor(DSValue _usdOracle, uint[] memory _rentPrices) public {
        setOracle(_usdOracle);
        setPrices(_rentPrices);
    }

    /**
     * @dev Sets the price oracle address
     * @param _usdOracle The address of the price oracle to use.
     */
    function setOracle(DSValue _usdOracle) public onlyOwner {
        usdOracle = _usdOracle;
        emit OracleChanged(address(_usdOracle));
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
     * @dev Returns the price to register or renew a name.
     * @param name The name being registered or renewed.
     * @param duration How long the name is being registered or extended for, in seconds.
     * @return The price of this renewal or registration, in wei.
     */
    function price(string calldata name, uint /*expires*/, uint duration) view external returns(uint) {
        uint len = name.strlen();
        if(len > rentPrices.length) {
            len = rentPrices.length;
        }
        require(len > 0);
        uint priceUSD = rentPrices[len - 1].mul(duration);

        // Price of one ether in attodollars
        uint ethPrice = uint(usdOracle.read());

        // priceUSD and ethPrice are both fixed-point values with 18dp, so we
        // multiply the numerator by 1e18 before dividing.
        return priceUSD.mul(1e18).div(ethPrice);
    }
}
