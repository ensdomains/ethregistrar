const ENS = artifacts.require('@ensdomains/ens/ENSRegistry');
const BaseRegistrar = artifacts.require('./BaseRegistrarImplementation');
const HashRegistrar = artifacts.require('@ensdomains/ens/HashRegistrar');
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
    const ownerAccount = accounts[0];
    const controllerAccount = accounts[1];
    const registrantAccount = accounts[2];
    const otherAccount = accounts[3];

    let ens;
	let interimRegistrar;
    let registrar;

	async function registerOldNames(names, account) {
        var hashes = names.map(sha3);
        var value = web3.toWei(0.01, 'ether');
        var bidHashes = await Promise.map(hashes, (hash) => interimRegistrar.shaBid(hash, account, value, SALT));
        await interimRegistrar.startAuctions(hashes);
        await Promise.map(bidHashes, (h) => interimRegistrar.newBid(h, {value: value, from: account}));
        await advanceTime(3 * DAYS + 1);
        await Promise.map(hashes, (hash) => interimRegistrar.unsealBid(hash, value, SALT, {from: account}));
        await advanceTime(2 * DAYS + 1);
        await Promise.map(hashes, (hash) => interimRegistrar.finalizeAuction(hash, {from: account}));
        for(var name of names) {
            assert.equal(await ens.owner(namehash.hash(name + '.eth')), account);
        }
    }

    before(async () => {
        ens = await ENS.new();

		interimRegistrar = await HashRegistrar.new(ens.address, namehash.hash('eth'), 1493895600);
		await ens.setSubnodeOwner('0x0', sha3('eth'), interimRegistrar.address);
		await registerOldNames(['name', 'name2'], registrantAccount);

		const now = (await web3.eth.getBlock('latest')).timestamp;
        registrar = await BaseRegistrar.new(ens.address, namehash.hash('eth'), now + 365 * DAYS, {from: ownerAccount});
        await registrar.addController(controllerAccount, {from: ownerAccount});
        await ens.setSubnodeOwner('0x0', sha3('eth'), registrar.address);
    });

	it('should report legacy names as unavailable during the migration period', async () => {
        assert.equal(await registrar.available(sha3('name2')), false);
    });

	it('should prohibit registration of legacy names during the migration period', async () => {
		await expectFailure(registrar.register(sha3("name2"), registrantAccount, 86400, {from: controllerAccount}));
		var registration = await registrar.registrations(sha3("name2"));
		assert.equal(registration[0], "0x0000000000000000000000000000000000000000");
		assert.equal(registration[1].toNumber(), 0);
	});

    it('should allow transfers from the old registrar', async () => {
		var balanceBefore = await web3.eth.getBalance(registrantAccount);
        var receipt = await interimRegistrar.transferRegistrars(sha3('name'), {gasPrice: 0, from: registrantAccount});
        var registration = await registrar.registrations(sha3('name'));
        assert.equal(registration[0], registrantAccount);
        assert.equal(registration[1], (await registrar.transferPeriodEnds()).toNumber());
    });

    it('should allow new registrations', async () => {
        var tx = await registrar.register(sha3("newname"), registrantAccount, 86400, {from: controllerAccount});
        var block = await web3.eth.getBlock(tx.receipt.blockHash);
		assert.equal(await ens.owner(namehash.hash("newname.eth")), registrantAccount);
        var registration = await registrar.registrations(sha3("newname"));
		assert.equal(registration[0], registrantAccount);
		assert.equal(registration[1].toNumber(), block.timestamp + 86400);
    });

    it('should allow renewals', async () => {
        var registration = await registrar.registrations(sha3("newname"));
        await registrar.renew(sha3("newname"), 86400, {from: controllerAccount});
        assert.equal((await registrar.registrations(sha3("newname")))[1].toNumber(), registration[1].add(86400).toNumber());
    });

    it('should only allow the controller to register', async () => {
        await expectFailure(registrar.register(sha3("foo"), otherAccount, 86400, {from: otherAccount}));
    });

    it('should only allow the controller to renew', async () => {
        await expectFailure(registrar.renew(sha3("newname"), 86400, {from: otherAccount}));
    });

    it('should not permit registration of already registered names', async () => {
        await expectFailure(registrar.register(sha3("newname"), otherAccount, 86400, {from: controllerAccount}));
		var registration = await registrar.registrations(sha3("newname"));
		assert.equal(registration[0], registrantAccount);
    });

    it('should not permit renewing a name that is not registered', async () => {
        await expectFailure(registrar.renew(sha3("name3"), 86400, {from: controllerAccount}));
    });

    it('should permit the owner to reclaim a name', async () => {
        await ens.setSubnodeOwner("0x0", sha3("eth"), accounts[0]);
        await ens.setSubnodeOwner(namehash.hash("eth"), sha3("newname"), 0);
        assert.equal(await ens.owner(namehash.hash("newname.eth")), "0x0000000000000000000000000000000000000000");
        await ens.setSubnodeOwner("0x0", sha3("eth"), registrar.address);
        await registrar.reclaim(sha3("newname"), {from: registrantAccount});
        assert.equal(await ens.owner(namehash.hash("newname.eth")), registrantAccount);
    });

    it('should prohibit anyone else from reclaiming a name', async () => {
        await expectFailure(registrar.reclaim(sha3("newname"), {from: otherAccount}));
    });

    it('should permit the owner to transfer a registration', async () => {
        await registrar.transfer(sha3("newname"), otherAccount, {from: registrantAccount});
        assert.equal((await registrar.registrations(sha3("newname")))[0], otherAccount);
        // Transfer does not update ENS without a call to reclaim.
        assert.equal(await ens.owner(namehash.hash("newname.eth")), registrantAccount);
        await registrar.transfer(sha3("newname"), registrantAccount, {from: otherAccount});
    });

    it('should prohibit anyone else from transferring a registration', async () => {
        await expectFailure(registrar.transfer(sha3("newname"), otherAccount, {from: otherAccount}));
    });

    it('should not permit transfer or reclaim during the grace period', async () => {
		// Advance to the grace period
        var ts = (await web3.eth.getBlock('latest')).timestamp;
        var registration = await registrar.registrations(sha3("newname"));
        await advanceTime(registration[1].toNumber() - ts + 3600);

        await expectFailure(registrar.transfer(sha3("newname"), otherAccount, {from: registrantAccount}));
        await expectFailure(registrar.reclaim(sha3("newname"), {from: registrantAccount}));
    });

    it('should allow renewal during the grace period', async () => {
        await registrar.renew(sha3("newname"), 86400, {from: controllerAccount});
    });

    it('should allow registration of an expired domain', async () => {
        var ts = (await web3.eth.getBlock('latest')).timestamp;
        var registration = await registrar.registrations(sha3("newname"));
        var grace = (await registrar.GRACE_PERIOD()).toNumber();
        await advanceTime(registration[1].toNumber() - ts + grace + 3600);
        await registrar.register(sha3("newname"), otherAccount, 86400, {from: controllerAccount});
        assert.equal((await registrar.registrations(sha3("newname")))[0], otherAccount);
    });

	// END OF MIGRATION PERIOD

    it('should show legacy names as available after the migration period', async () => {
		var ts = (await web3.eth.getBlock('latest')).timestamp;
        await advanceTime((await registrar.transferPeriodEnds()).toNumber() - ts + 3600);
        assert.equal(await registrar.available('name2'), true);
    });

    it('should permit registration of legacy names after the migration period', async () => {
        await registrar.register(sha3("name2"), accounts[1], 86400, {from: controllerAccount});
		assert.equal(await ens.owner(namehash.hash("name2.eth")), accounts[1]);
    });
});
