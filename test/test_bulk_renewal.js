const ENS = artifacts.require('@ensdomains/ens/ENSRegistry');
const HashRegistrar = artifacts.require('@ensdomains/ens/HashRegistrar');
const PublicResolver = artifacts.require('@ensdomains/resolver/PublicResolver');
const BaseRegistrar = artifacts.require('./BaseRegistrarImplementation');
const ETHRegistrarController = artifacts.require('./ETHRegistrarController');
const SimplePriceOracle = artifacts.require('./SimplePriceOracle');
const BulkRenewal = artifacts.require('./BulkRenewal');
var Promise = require('bluebird');

const namehash = require('eth-ens-namehash');
const sha3 = require('web3-utils').sha3;
const toBN = require('web3-utils').toBN;

const NULL_ADDRESS = "0x0000000000000000000000000000000000000000"
const ETH_LABEL = sha3('eth');
const ETH_NAMEHASH = namehash.hash('eth');

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

contract('ETHRegistrarController', function (accounts) {
	let ens;
	let resolver;
	let baseRegistrar;
	let controller;
	let priceOracle;
	let bulkRenewal;

	const secret = "0x0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF";
	const ownerAccount = accounts[0]; // Account that owns the registrar
	const registrantAccount = accounts[1]; // Account that owns test names

	before(async () => {
		// Create a registry
		ens = await ENS.new();

		// Create a public resolver
		resolver = await PublicResolver.new(ens.address);

		// Create a base registrar
		baseRegistrar = await BaseRegistrar.new(ens.address, namehash.hash('eth'), {from: ownerAccount});

		// Set up a dummy price oracle and a controller
		priceOracle = await SimplePriceOracle.new(1);
		controller = await ETHRegistrarController.new(
			baseRegistrar.address,
			priceOracle.address,
			600,
			86400,
			{from: ownerAccount});
		await baseRegistrar.addController(controller.address, {from: ownerAccount});
		await baseRegistrar.addController(ownerAccount, {from: ownerAccount});
		// Create the bulk registration contract
		bulkRenewal = await BulkRenewal.new(ens.address);

		// Configure a resolver for .eth and register the controller interface
		// then transfer the .eth node to the base registrar.
		await ens.setSubnodeRecord('0x0', ETH_LABEL, ownerAccount, resolver.address, 0);
		await resolver.setInterface(ETH_NAMEHASH, '0x018fac06', controller.address);
		await ens.setOwner(ETH_NAMEHASH, baseRegistrar.address);

		// Register some names
		for(const name of ['test1', 'test2', 'test3']) {
			await baseRegistrar.register(sha3(name), registrantAccount, 31536000);
		}
  });

	it('should return the cost of a bulk renewal', async () => {
		assert.equal(await bulkRenewal.rentPrice(['test1', 'test2'], 86400), 86400 * 2);
	});

	it('should raise an error trying to renew a nonexistent name', async () => {
		await expectFailure(bulkRenewal.renewAll(['foobar'], 86400));
	})

	it('should permit bulk renewal of names', async () => {
		const oldExpiry = await baseRegistrar.nameExpires(sha3('test2'));
		const tx = await bulkRenewal.renewAll(['test1', 'test2'], 86400, {value: 86400 * 2});
		assert.equal(tx.receipt.status, true);
		const newExpiry = await baseRegistrar.nameExpires(sha3('test2'));
		assert.equal(newExpiry - oldExpiry, 86400);
	});
});
