const ENS = artifacts.require('@ensdomains/ens/ENSRegistry');
const BaseRegistrar = artifacts.require('./BaseRegistrar');
const SimplePriceOracle = artifacts.require('./SimplePriceOracle');
var Promise = require('bluebird');

const namehash = require('eth-ens-namehash');
const sha3 = require('web3-utils').sha3;

const DAYS = 24 * 60 * 60;
const SALT = sha3('foo');
const advanceTime = Promise.promisify(function(delay, done) {
	web3.currentProvider.sendAsync({
		jsonrpc: "2.0",
		"method": "evm_increaseTime",
		params: [delay]}, done)
});

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

contract('BaseRegistrar', function (accounts) {

    let ens;
    let priceOracle;
    let registrar;

    before(async () => {
        ens = await ENS.new();
        priceOracle = await SimplePriceOracle.new(1);
        registrar = await BaseRegistrar.new(ens.address, namehash.hash('eth'), priceOracle.address);
        await ens.setSubnodeOwner('0x0', sha3('eth'), registrar.address);
    });

    it('should report unused names as available', async () => {
        assert.equal(await registrar.available(sha3('available')), true);
    });

    it('should allow new registrations', async () => {
        var tx = await registrar.register("name", accounts[0], 86400, {value: 86400});
        var block = await web3.eth.getBlock(tx.receipt.blockHash);
		assert.equal(await ens.owner(namehash.hash("name.eth")), accounts[0]);
        var registration = await registrar.registrations(sha3("name"));
		assert.equal(registration[0], accounts[0]);
		assert.equal(registration[1].toNumber(), block.timestamp + 86400);
    });

    it('should refund excess registration funds', async () => {
        var balanceBefore = await web3.eth.getBalance(accounts[0]);
        await registrar.register("name2", accounts[0], 86400, {value: 1000000, gasPrice: 0});
        assert.equal((await web3.eth.getBalance(accounts[0])) - balanceBefore, -86400);
    });

    it('should report registered names as unavailable', async () => {
        assert.equal(await registrar.available('name'), false);
    });

    it('should not permit registration of already registered names', async () => {
        await expectFailure(registrar.register("name", accounts[1], 86400, {value: 86400}));
		var registration = await registrar.registrations(sha3("name"));
		assert.equal(registration[0], accounts[0]);
    });

    it('should allow anyone to renew a name', async () => {
        var registration = await registrar.registrations(sha3("name"));
        await registrar.renew("name", 86400, {value: 86400});
        var newRegistration = await registrar.registrations(sha3("name"));
        assert.equal(newRegistration[1] - registration[1], 86400);
    });

    it('should not permit renewing a name that is not registered', async () => {
        await expectFailure(registrar.renew("name3", 86400, {value: 86400}));
    });

    it('should require sufficient value for a renewal', async () => {
        await expectFailure(registrar.renew("name", 86400));
    });

    it('should refund excess renewal funds', async () => {
        var balanceBefore = await web3.eth.getBalance(accounts[0]);
        await registrar.renew("name", 86400, {value: 1000000, gasPrice: 0})
        assert.equal((await web3.eth.getBalance(accounts[0])) - balanceBefore, 86400);
    });

    it('should permit the owner to reclaim a name', async () => {
        await ens.setSubnodeOwner("0x0", sha3("eth"), accounts[0]);
        await ens.setSubnodeOwner(namehash.hash("eth"), sha3("name"), 0);
        assert.equal(await ens.owner(namehash.hash("name.eth")), "0x0000000000000000000000000000000000000000");
        await ens.setSubnodeOwner("0x0", sha3("eth"), registrar.address);
        await registrar.reclaim("name");
        assert.equal(await ens.owner(namehash.hash("name.eth")), accounts[0]);
    });

    it('should prohibit anyone else from reclaiming a name', async () => {
        await expectFailure(registrar.reclaim("name", {from: accounts[1]}));
    });

    it('should permit the owner to transfer a registration', async () => {
        await registrar.transfer("name", accounts[1]);
        assert.equal((await registrar.registrations(sha3("name")))[0], accounts[1]);
        assert.equal(await ens.owner(namehash.hash("name.eth")), accounts[1]);
        await registrar.transfer("name", accounts[0], {from: accounts[1]});
    });

    it('should prohibit anyone else from transferring a registration', async () => {
        await expectFailure(registrar.transfer("test", accounts[1], {from: accounts[1]}));
    });

    it('should not permit transfer or reclaim during the grace period', async () => {
        await expectFailure(registrar.transfer("test", accounts[1]));
        await expectFailure(registrar.reclaim("test"));
    });

    it('should allow renewal during the grace period', async () =>  {
        await advanceTime(86400);
        await registrar.renew("name", 86400, {value: 86400});
    });

    it('should allow the registrar owner to withdraw funds', async () => {
        var registrarBalance = await web3.eth.getBalance(registrar.address);
        var balanceBefore = await web3.eth.getBalance(accounts[0]);
        await registrar.withdraw({gasPrice: 0});
        assert.equal((await web3.eth.getBalance(accounts[0])) - balanceBefore, registrarBalance.toNumber());
    });
});
