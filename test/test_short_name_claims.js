const ENS = artifacts.require('@ensdomains/ens/ENSRegistry');
const BaseRegistrar = artifacts.require('./BaseRegistrarImplementation');
const HashRegistrar = artifacts.require('@ensdomains/ens/HashRegistrar');
const ShortNameClaims = artifacts.require('./ShortNameClaims');
const DNSSEC = artifacts.require('./mocks/DummyDNSSEC.sol');
const SimplePriceOracle = artifacts.require('./SimplePriceOracle.sol');
var Promise = require('bluebird');
const dns = require('../lib/dns.js');

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
		assert.include(
			error.message,
			'revert'
		);
	}
	if(tx !== undefined) {
		assert.equal(parseInt(tx.receipt.status), 0);
	}
}

function makeTXTRecord(name, addr) {
	return dns.hexEncodeTXT({
		name: name,
		klass: 1,
		ttl: 86400,
		text: ['a=' + addr]
	});
}

contract('ShortNameClaims', function (accounts) {
	const ownerAccount = accounts[0];
	const claimantAccount = accounts[1];
	const registrarOwner = accounts[2];

	let ens;
	let interimRegistrar;
	let registrar;
	let claims;
	let dnssec;

	async function setTXTRecord(name, addr) {
		const proof = makeTXTRecord(name, addr);

		const now = (await web3.eth.getBlock('latest')).timestamp;
		await dnssec.setData(16, dns.hexEncodeName(name), now, now, proof);
		return proof;
	}

	before(async () => {
		ens = await ENS.new();

		interimRegistrar = await HashRegistrar.new(ens.address, namehash.hash('eth'), 1493895600);

		const now = (await web3.eth.getBlock('latest')).timestamp;
		registrar = await BaseRegistrar.new(ens.address, interimRegistrar.address, namehash.hash('eth'), now + 365 * DAYS, {from: ownerAccount});
		await ens.setSubnodeOwner('0x0', sha3('eth'), registrar.address);

		dnssec = await DNSSEC.new();
		const priceOracle = await SimplePriceOracle.new(1);

		claims = await ShortNameClaims.new(dnssec.address, priceOracle.address, registrar.address);
		await registrar.addController(claims.address, {from: ownerAccount});
		await registrar.transferOwnership(registrarOwner);
	});

	it('should permit a DNS name owner to register a claim on an exact match', async () => {
		const proof = await setTXTRecord("_ens.foo.test.", claimantAccount);

		const tx = await claims.submitExactClaim(dns.hexEncodeName('foo.test.'), '0x', proof, {value: 31536001});
		const logs = tx.receipt.logs;
		assert.equal(logs.length, 1);
		assert.equal(logs[0].event, "ClaimSubmitted");
		assert.equal(logs[0].args.claimed, "foo");
		assert.equal(logs[0].args.dnsname, dns.hexEncodeName('foo.test.'));
		assert.equal(logs[0].args.paid.toNumber(), 31536000);

		assert.equal(await web3.eth.getBalance(claims.address), 31536000);

		assert.equal(await claims.claimCount(), 1);

		const claimId = await claims.computeClaimId("foo", dns.hexEncodeName("foo.test."));
		const { labelHash, claimant, paid } = await claims.claims(claimId);
		assert.equal(labelHash, sha3("foo"));
		assert.equal(claimant, claimantAccount);
		assert.equal(paid.toNumber(), 31536000);
	});

	it('should permit a DNS name owner to register a claim on a prefix ending with eth', async () => {
		const proof = await setTXTRecord("_ens.fooeth.test.", claimantAccount);
		const tx = await claims.submitPrefixClaim(dns.hexEncodeName('fooeth.test.'), '0x', proof, {value: 31536000});
		const logs = tx.receipt.logs;
		assert.equal(logs.length, 1);
		assert.equal(logs[0].event, "ClaimSubmitted");
		assert.equal(logs[0].args.claimed, "foo");
	});

	it('should fail to register a prefix of a name if its suffix is not eth', async () => {
		const proof = makeTXTRecord('_ens.foobar.test.', claimantAccount);
		await expectFailure(claims.submitPrefixClaim(dns.hexEncodeName('foobar.test.'), '0x', proof, {value: 31536000}));
	});

	it('should permit a DNS name owner to register a claim on a combined name + tld', async () => {
		const proof = await setTXTRecord("_ens.foo.tv.", claimantAccount);
		const tx = await claims.submitCombinedClaim(dns.hexEncodeName('foo.tv.'), '0x', proof, {value: 31536000});
		const logs = tx.receipt.logs;
		assert.equal(logs.length, 1);
		assert.equal(logs[0].event, "ClaimSubmitted");
		assert.equal(logs[0].args.claimed, "footv");
	});

	it('should fail if the proof is not in the oracle', async () => {
		const proof = makeTXTRecord("_ens.bar.test.", claimantAccount);
		await expectFailure(claims.submitExactClaim(dns.hexEncodeName('bar.test.'), '0x', proof, {value: 31536001}));
	});

	it('should not allow subdomains to be used in a claim', async () => {
		const proof = await setTXTRecord("_ens.foo.bar.test.", claimantAccount);

		await expectFailure(claims.submitExactClaim(dns.hexEncodeName('foo.bar.test.'), '0x', proof, {value: 31536001}));
	});

	it('should fail if the name does not match the proof', async () => {
		const proof = await setTXTRecord("_ens.foo.test.", claimantAccount);

		await expectFailure(claims.submitExactClaim(dns.hexEncodeName('bar.test.'), '0x', proof, {value: 31536001}));
	});

	it('should fail with insufficient payment', async () => {
		const proof = await setTXTRecord("_ens.bar.test.", claimantAccount);
		await expectFailure(claims.submitExactClaim(dns.hexEncodeName('bar.test.'), '0x', proof, {value: 1000}));
	});

	it('should reject claims that are too long or too short', async () => {
		const proof = await setTXTRecord("_ens.hi.test.", claimantAccount);
		await expectFailure(claims.submitExactClaim(dns.hexEncodeName('hi.test.'), '0x', proof, {value: 31536000}));
	});

	it('should reject duplicate claims', async () => {
		const proof = makeTXTRecord("_ens.foo.test.", claimantAccount);
		await expectFailure(claims.submitExactClaim(dns.hexEncodeName("foo.test."), '0x', proof, {value: 31536000}));
	});

	it('should not allow non-owners to approve claims', async () => {
		const claimId = await claims.computeClaimId("footv", dns.hexEncodeName("foo.tv."));
		await expectFailure(claims.approveClaim(claimId, {from: claimantAccount}));
	});

	it('should allow the owner to approve claims', async () => {
		const balanceBefore = toBN(await web3.eth.getBalance(registrarOwner));

		const claimId = await claims.computeClaimId("foo", dns.hexEncodeName("foo.test."));
		const tx = await claims.approveClaim(claimId);
		const logs = tx.receipt.logs;
		assert.isAtLeast(logs.length, 1);
		assert.equal(logs[0].event, "ClaimApproved");
		assert.equal(logs[0].args.claimId, claimId);

		const balanceAfter = toBN(await web3.eth.getBalance(registrarOwner));
		assert.equal(balanceAfter.sub(balanceBefore).toNumber(), 31536000);
		assert.equal(await claims.claimCount(), 2);
	});

	it('should not allow approving nonexistent claims', async () => {
		const claimId = await claims.computeClaimId("foo", dns.hexEncodeName("foo.test."));
		await expectFailure(claims.approveClaim(claimId));
	})

	it('should not permit approving a claim for an already registered name', async () => {
		const claimId = await claims.computeClaimId("foo", dns.hexEncodeName("fooeth.test."));
		await expectFailure(claims.approveClaim(claimId));
	});

	it('should not allow non-owners to decline claims', async () => {
		const claimId = await claims.computeClaimId("foo", dns.hexEncodeName("fooeth.test."));
		await expectFailure(claims.declineClaim(claimId, {from: claimantAccount}));
	});

	it('should allow the owner to decline claims', async () => {
		const balanceBefore = toBN(await web3.eth.getBalance(claimantAccount));

		const claimId = await claims.computeClaimId("foo", dns.hexEncodeName("fooeth.test."));
		const tx = await claims.declineClaim(claimId);
		const logs = tx.receipt.logs;
		assert.isAtLeast(logs.length, 1);
		assert.equal(logs[0].event, "ClaimDeclined");
		assert.equal(logs[0].args.claimId, claimId);

		const balanceAfter = toBN(await web3.eth.getBalance(claimantAccount));
		assert.equal(balanceAfter.sub(balanceBefore).toNumber(), 31536000);
		assert.equal(await claims.claimCount(), 1);
	});

	it('should not allow declining nonexistent claims', async () => {
		const claimId = await claims.computeClaimId("foo", dns.hexEncodeName("fooeth.test."));
		await expectFailure(claims.declineClaim(claimId));
	});
});
