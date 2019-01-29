const ENS = artifacts.require('@ensdomains/ens/ENSRegistry');
const BaseRegistrar = artifacts.require('./BaseRegistrarImplementation');
const HashRegistrar = artifacts.require('@ensdomains/ens/HashRegistrar');
var Promise = require('bluebird');

const namehash = require('eth-ens-namehash');
const sha3 = require('web3-utils').sha3;
const toBN = require('web3-utils').toBN;

const DAYS = 24 * 60 * 60;
const SALT = sha3('foo');
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const ZERO_HASH = "0x0000000000000000000000000000000000000000000000000000000000000000";

const advanceTime = Promise.promisify(function(delay, done) {
	web3.currentProvider.send({
		jsonrpc: "2.0",
		"method": "evm_increaseTime",
		params: [delay]}, done)
	}
);

async function expectFailure(call) {
	let tx;
	try {
		tx = await call;
	} catch (error) {
		// Assert ganache revert exception
		assert.equal(
			error.message,
			'Returned error: VM Exception while processing transaction: revert'
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
		var value = toBN(10000000000000000);
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
		await expectFailure(registrar.ownerOf(sha3("name2")));
		assert.equal((await registrar.nameExpires(sha3("name2"))).toNumber(), 0);
	});

	it('should prohibit renewals of un-migrated names', async () => {
		await expectFailure(registrar.renew(sha3("name"), 86400, {from: controllerAccount}));
	});

	it('should allow transfers from the old registrar', async () => {
		var balanceBefore = await web3.eth.getBalance(registrantAccount);
		await interimRegistrar.transferRegistrars(sha3('name'), {gasPrice: 0, from: registrantAccount});
		assert.equal(await registrar.ownerOf(sha3("name")), registrantAccount);
		assert.equal((await (registrar.nameExpires(sha3("name")))).toNumber(), (await registrar.transferPeriodEnds()).toNumber());
	});

	it('should allow new registrations', async () => {
		var tx = await registrar.register(sha3("newname"), registrantAccount, 86400, {from: controllerAccount});
		var block = await web3.eth.getBlock(tx.receipt.blockHash);
		assert.equal(await ens.owner(namehash.hash("newname.eth")), registrantAccount);
		assert.equal(await registrar.ownerOf(sha3("newname")), registrantAccount);
		assert.equal((await registrar.nameExpires(sha3("newname"))).toNumber(), block.timestamp + 86400);
	});

	it('should allow renewals', async () => {
		var oldExpires = await registrar.nameExpires(sha3("newname"));
		await registrar.renew(sha3("newname"), 86400, {from: controllerAccount});
		assert.equal((await registrar.nameExpires(sha3("newname"))).toNumber(), oldExpires.add(toBN(86400)).toNumber());
	});

	it('should only allow the controller to register', async () => {
		await expectFailure(registrar.register(sha3("foo"), otherAccount, 86400, {from: otherAccount}));
	});

	it('should only allow the controller to renew', async () => {
		await expectFailure(registrar.renew(sha3("newname"), 86400, {from: otherAccount}));
	});

	it('should not permit registration of already registered names', async () => {
		await expectFailure(registrar.register(sha3("newname"), otherAccount, 86400, {from: controllerAccount}));
		assert.equal(await registrar.ownerOf(sha3("newname")), registrantAccount);
	});

	it('should not permit renewing a name that is not registered', async () => {
		await expectFailure(registrar.renew(sha3("name3"), 86400, {from: controllerAccount}));
	});

	it('should permit the owner to reclaim a name', async () => {
		await ens.setSubnodeOwner(ZERO_HASH, sha3("eth"), accounts[0]);
		await ens.setSubnodeOwner(namehash.hash("eth"), sha3("newname"), ZERO_ADDRESS);
		assert.equal(await ens.owner(namehash.hash("newname.eth")), ZERO_ADDRESS);
		await ens.setSubnodeOwner(ZERO_HASH, sha3("eth"), registrar.address);
		await registrar.reclaim(sha3("newname"), {from: registrantAccount});
		assert.equal(await ens.owner(namehash.hash("newname.eth")), registrantAccount);
	});

	it('should prohibit anyone else from reclaiming a name', async () => {
		await expectFailure(registrar.reclaim(sha3("newname"), {from: otherAccount}));
	});

	it('should permit the owner to transfer a registration', async () => {
		await registrar.transferFrom(registrantAccount, otherAccount, sha3("newname"), {from: registrantAccount});
		assert.equal((await registrar.ownerOf(sha3("newname"))), otherAccount);
		// Transfer does not update ENS without a call to reclaim.
		assert.equal(await ens.owner(namehash.hash("newname.eth")), registrantAccount);
		await registrar.transferFrom(otherAccount, registrantAccount, sha3("newname"), {from: otherAccount});
	});

	it('should prohibit anyone else from transferring a registration', async () => {
		await expectFailure(registrar.transferFrom(otherAccount, otherAccount, sha3("newname"), {from: otherAccount}));
	});

	it('should not permit transfer or reclaim during the grace period', async () => {
		// Advance to the grace period
		var ts = (await web3.eth.getBlock('latest')).timestamp;
		await advanceTime((await registrar.nameExpires(sha3("newname"))).toNumber() - ts + 3600);

		await expectFailure(registrar.transferFrom(registrantAccount, otherAccount, sha3("newname"), {from: registrantAccount}));
		await expectFailure(registrar.reclaim(sha3("newname"), {from: registrantAccount}));
	});

	it('should allow renewal during the grace period', async () => {
		await registrar.renew(sha3("newname"), 86400, {from: controllerAccount});
	});

	it('should allow registration of an expired domain', async () => {
		var ts = (await web3.eth.getBlock('latest')).timestamp;
		var expires = await registrar.nameExpires(sha3("newname"));
		var grace = await registrar.GRACE_PERIOD();
		await advanceTime(expires.toNumber() - ts + grace.toNumber() + 3600);
		expectFailure(registrar.ownerOf(sha3("newname"))); // ownerOf reverts for nonexistent names
		await registrar.register(sha3("newname"), otherAccount, 86400, {from: controllerAccount});
		assert.equal(await registrar.ownerOf(sha3("newname")), otherAccount);
	});

	// END OF MIGRATION PERIOD

	it('should show legacy names as available after the migration period', async () => {
		var ts = (await web3.eth.getBlock('latest')).timestamp;
		await advanceTime((await registrar.transferPeriodEnds()).toNumber() - ts + 3600);
		assert.equal(await registrar.available(sha3('name2')), true);
	});

	it('should permit registration of legacy names after the migration period', async () => {
		await registrar.register(sha3("name2"), accounts[1], 86400, {from: controllerAccount});
		assert.equal(await ens.owner(namehash.hash("name2.eth")), accounts[1]);
	});
});
