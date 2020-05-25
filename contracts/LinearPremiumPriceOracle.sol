pragma solidity >=0.5.0;

import "./SafeMath.sol";
import "./StablePriceOracle.sol";

contract LinearPremiumPriceOracle is StablePriceOracle {
    using SafeMath for *;

    uint GRACE_PERIOD = 90 days;

    uint public initialPremium;
    uint public premiumDecreaseRate;

    constructor(DSValue _usdOracle, uint[] memory _rentPrices, uint _initialPremium, uint _premiumDecreaseRate) public
        StablePriceOracle(_usdOracle, _rentPrices)
    {
        initialPremium = _initialPremium;
        premiumDecreaseRate = _premiumDecreaseRate;
    }

    function _premium(string memory name, uint expires, uint duration) internal view returns(uint) {
        expires = expires.add(GRACE_PERIOD);
        if(expires > now) {
            // No premium for renewals
            return 0;
        }

        // Calculate the discount off the maximum premium
        uint discount = premiumDecreaseRate.mul(now.sub(expires));

        if(discount > initialPremium) {
            return 0;
        }
        
        return initialPremium.sub(discount);
    }

    function timeUntilPremium(uint expires, uint amount) external view returns(uint) {
        expires = expires.add(GRACE_PERIOD);
        uint discount = initialPremium.sub(amount);
        uint duration = discount.div(premiumDecreaseRate);
        return now + duration;
    }
}
