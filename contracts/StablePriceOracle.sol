pragma solidity ^0.5.0;

import "./BasePriceOracle.sol";
import "./SafeMath.sol";
import "./StringUtils.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

interface DSValue {
    function read() external view returns (bytes32);
}

// StablePriceOracle sets a price in USD, based on an oracle.
contract StablePriceOracle is BasePriceOracle {
    using SafeMath for *;
    using StringUtils for *;

    // Oracle address
    DSValue public usdOracle;

    event OracleChanged(address oracle);

    constructor(DSValue _usdOracle, uint[] memory _rentPrices, address registrar) public BasePriceOracle(_rentPrices, registrar) {
        setOracle(_usdOracle);
    }

    /**
     * @dev Sets the price oracle address
     * @param _usdOracle The address of the price oracle to use.
     */
    function setOracle(DSValue _usdOracle) public onlyOwner {
        usdOracle = _usdOracle;
        emit OracleChanged(address(_usdOracle));
    }

    function basePriceToWei(uint basePrice) internal view returns(uint) {
        uint ethPrice = uint(usdOracle.read());
        return basePrice.mul(1e18).div(ethPrice);
    }
}
