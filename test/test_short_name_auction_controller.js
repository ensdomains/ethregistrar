const ENS = artifacts.require('@ensdomains/ens/ENSRegistry');
const HashRegistrar = artifacts.require('@ensdomains/ens/HashRegistrar');
const BaseRegistrar = artifacts.require('./BaseRegistrarImplementation');
const ShortNameAuctionController = artifacts.require('./ShortNameAuctionController');
const DummyProxyRegistry = artifacts.require('./mocks/DummyProxyRegistry');
var Promise = require('bluebird');

const namehash = require('eth-ens-namehash');
const sha3 = require('web3-utils').sha3;
const toBN = require('web3-utils').toBN;

const DAYS = 24 * 60 * 60;

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

contract('ShortNameAuctionController', function (accounts) {
	let ens;
	let baseRegistrar;
	let controller;
	let priceOracle;

	const ownerAccount = accounts[0]; // Account that owns the registrar
	const openseaAccount = accounts[1];
	const openseaProxyAccount = accounts[2];
	const registrantAccount = accounts[3];

	before(async () => {
		ens = await ENS.new();

		baseRegistrar = await BaseRegistrar.new(ens.address, namehash.hash('eth'), {from: ownerAccount});
		await ens.setSubnodeOwner('0x0', sha3('eth'), baseRegistrar.address);

		const proxy = await DummyProxyRegistry.new(openseaProxyAccount);

		controller = await ShortNameAuctionController.new(
			baseRegistrar.address,
			proxy.address,
			openseaAccount);
		await baseRegistrar.addController(controller.address, {from: ownerAccount});
	});

	it('should report 3-6 character names as available', async () => {
		assert.equal(await controller.available('name'), true);
	});

	it('should report too long names as unavailable', async () => {
		assert.equal(await controller.available('longname'), false);
	});

	it('should report too short names as unavailable', async () => {
		assert.equal(await controller.available('ha'), false);
	});

	it('should permit the opensea address to register a name', async () => {
		var tx = await controller.register('foo', registrantAccount, {from: openseaAccount});
		assert.equal(tx.logs.length, 1);
		assert.equal(tx.logs[0].event, "NameRegistered");
		assert.equal(tx.logs[0].args.name, "foo");
		assert.equal(tx.logs[0].args.owner, registrantAccount);

		assert.equal(await ens.owner(namehash.hash("foo.eth")), registrantAccount);
		assert.equal(await baseRegistrar.ownerOf(sha3("foo")), registrantAccount);
		assert.equal(await baseRegistrar.nameExpires(sha3("foo")), (await web3.eth.getBlock(tx.receipt.blockNumber)).timestamp + 31536000);
	});

	it('should not allow registering an already-registered name', async () => {
		await expectFailure(controller.register('foo', registrantAccount, {from: openseaAccount}));
	})

	it('should permit the opensea proxy address to register a name', async () => {
		var tx = await controller.register('bar', registrantAccount, {from: openseaAccount});
		assert.equal(tx.logs.length, 1);
		assert.equal(tx.logs[0].event, "NameRegistered");
		assert.equal(tx.logs[0].args.name, "bar");
		assert.equal(tx.logs[0].args.owner, registrantAccount);
	});

	it('should not permit anyone else to register a name', async () => {
		await expectFailure(controller.register('baz', registrantAccount, {from: registrantAccount}));
	});
});
