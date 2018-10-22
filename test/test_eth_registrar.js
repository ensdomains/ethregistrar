const ENS = artifacts.require('@ensdomains/ens/ENSRegistry');
const InterimRegistrar = artifacts.require('@ensdomains/ens/Registrar');
const ETHRegistrar = artifacts.require('./ETHRegistrar');
const SimplePriceOracle = artifacts.require('./SimplePriceOracle');
var Promise = require('bluebird');

const namehash = require('eth-ens-namehash');
const sha3 = require('web3-utils').sha3;

const DAYS = 24 * 60 * 60;
const SALT = sha3('foo');
const TRANSFER_COST = web3.toWei(0.005, 'ether');
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

contract('ETHRegistrar', function (accounts) {
    let ens;
    let interimRegistrar;
    let registrar;
	let priceOracle;

    async function registerOldNames(names) {
        var hashes = names.map(sha3);
        var value = web3.toWei(0.01, 'ether');
        var bidHashes = await Promise.map(hashes, (hash) => interimRegistrar.shaBid(hash, accounts[0], value, SALT));
        await interimRegistrar.startAuctions(hashes);
        await Promise.map(bidHashes, (h) => interimRegistrar.newBid(h, {value: value}));
        await advanceTime(3 * DAYS + 1);
        await Promise.map(hashes, (hash) => interimRegistrar.unsealBid(hash, value, SALT));
        await advanceTime(2 * DAYS + 1);
        await Promise.map(hashes, (hash) => interimRegistrar.finalizeAuction(hash));
        for(var name of names) {
            assert.equal(await ens.owner(namehash.hash(name + '.eth')), accounts[0]);
        }
    }

    before(async () => {
        ens = await ENS.new();
        interimRegistrar = await InterimRegistrar.new(ens.address, namehash.hash('eth'), 1493895600);
		priceOracle = await SimplePriceOracle.new(1);
        registrar = await ETHRegistrar.new(
			ens.address,
			namehash.hash('eth'),
			priceOracle.address,
			interimRegistrar.address,
			TRANSFER_COST);

        await ens.setSubnodeOwner('0x0', sha3('eth'), interimRegistrar.address);
        await registerOldNames(['name', 'name2']);
        await ens.setSubnodeOwner('0x0', sha3('eth'), registrar.address);
    });

    it('should report legacy names as unavailable during the migration period', async () => {
        assert.equal(await registrar.available('name2'), false);
    });

	it('should prohibit registration of legacy names during the migration period', async () => {
		await expectFailure(registrar.register("name2", accounts[0], 86400, {value: 86400}));
		var registration = await registrar.registrations(sha3("name2"));
		assert.equal(registration[0], "0x0000000000000000000000000000000000000000");
		assert.equal(registration[1].toNumber(), 0);
	});

    it('should allow transfers from the old registrar', async () => {
		var balanceBefore = await web3.eth.getBalance(accounts[0]);
        var receipt = await interimRegistrar.transferRegistrars(sha3('name'), {gasPrice: 0});
		assert.equal(await web3.eth.getBalance(registrar.address), TRANSFER_COST);
		assert.equal((await web3.eth.getBalance(accounts[0])) - balanceBefore, web3.toWei(0.01, 'ether') - TRANSFER_COST);
        var registration = await registrar.registrations(sha3('name'));
        assert.equal(registration[0], accounts[0]);
        var now = await web3.eth.getBlock(receipt.receipt.blockHash).timestamp;
        assert.equal(registration[1], now + (await registrar.INITIAL_RENEWAL_DURATION()).toNumber());
    });

    // END OF MIGRATION PERIOD

    it('should show legacy names as available after the migration period', async () => {
        await advanceTime((await registrar.TRANSFER_PERIOD()).toNumber());
        assert.equal(await registrar.available('name2'), true);
    });

    it('should permit registration of legacy names after the migration period', async () => {
        await registrar.register("name2", accounts[1], 86400, {value: 86400});
		assert.equal(await ens.owner(namehash.hash("name2.eth")), accounts[1]);
    });
});
