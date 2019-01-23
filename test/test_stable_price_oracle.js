const DummyOracle = artifacts.require('./DummyOracle');
const StablePriceOracle = artifacts.require('./StablePriceOracle');
var Promise = require('bluebird');

const toBN = require('web3-utils').toBN;

const DAYS = 24 * 60 * 60;

async function expectFailure(call) {
    let tx;
    try {
        tx = await call;
    } catch (error) {
        // Assert ganache revert exception
        assert.equal(
            error.message,
            'VM Exception while processing transaction: revert'
        );
    }
    if(tx !== undefined) {
        assert.equal(parseInt(tx.receipt.status), 0);
    }
}

contract('StablePriceOracle', function (accounts) {
    let priceOracle;

    before(async () => {
        // Dummy oracle with 1 ETH == 10 USD
        var dummyOracle = await DummyOracle.new(toBN(10000000000000000000));
        // 4 attousd per second for 3 character names, 2 attousd per second for 4 character names,
        // 1 attousd per second for longer names.
        priceOracle = await StablePriceOracle.new(dummyOracle.address, [0, 0, 4, 2, 1]);
    });

    it('should return correct prices', async () => {
        assert.equal((await priceOracle.price("foo", 0, 3600)).toNumber(), 1440);
        assert.equal((await priceOracle.price("quux", 0, 3600)).toNumber(), 720);
        assert.equal((await priceOracle.price("fubar", 0, 3600)).toNumber(), 360);
        assert.equal((await priceOracle.price("foobie", 0, 3600)).toNumber(), 360);
    });

    it('should work with larger values', async () => {
        // 1 USD per second!
        await priceOracle.setPrices([toBN("1000000000000000000")]);
        assert.equal((await priceOracle.price("foo", 0, 86400)).toString(), "8640000000000000000000");
    })
});
