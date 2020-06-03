pragma solidity >=0.5.0;

import "./SafeMath.sol";
import "./StablePriceOracle.sol";

contract LinearPremiumPriceOracle is StablePriceOracle {
    using SafeMath for *;

    uint GRACE_PERIOD = 90 days;

    uint public initialPremium;
    uint public premiumDecreaseRate;

    bytes4 constant private TIME_UNTIL_PREMIUM_ID = bytes4(keccak256("timeUntilPremium(uint,uint"));

    constructor(DSValue _usdOracle, uint[] memory _rentPrices, uint _initialPremium, uint _premiumDecreaseRate) public
        StablePriceOracle(_usdOracle, _rentPrices)
    {
        initialPremium = _initialPremium;
        premiumDecreaseRate = _premiumDecreaseRate;
    }

    function _premium(string memory name, uint expires, uint /*duration*/) internal view returns(uint) {
        expires = expires.add(GRACE_PERIOD);
        if(expires > now) {
            // No premium for renewals
            return 0;
        }

        // Calculate the discount off the maximum premium
        uint discount = premiumDecreaseRate.mul(now.sub(expires));

        // If we've run out the premium period, return 0.
        if(discount > initialPremium) {
            return 0;
        }
        
        return initialPremium - discount;
    }

    /**
     * @dev Returns the timestamp at which a name with the specified expiry date will have
     *      the specified re-registration price premium.
     * @param expires The timestamp at which the name expires.
     * @param amount The amount, in wei, the caller is willing to pay
     * @return The timestamp at which the premium for this domain will be `amount`.
     */
    function timeUntilPremium(uint expires, uint amount) external view returns(uint) {
        amount = weiToAttoUSD(amount);
        require(amount <= initialPremium);

        expires = expires.add(GRACE_PERIOD);

        uint discount = initialPremium.sub(amount);
        uint duration = discount.div(premiumDecreaseRate);
        return expires.add(duration);
    }

    function supportsInterface(bytes4 interfaceID) public view returns (bool) {
        return (interfaceID == TIME_UNTIL_PREMIUM_ID) || super.supportsInterface(interfaceID);
    }
}
