const ENS = artifacts.require('@ensdomains/ens/ENSRegistry.sol');
const InterimRegistrar = artifacts.require('@ensdomains/ens/HashRegistrarSimplified.sol');

const namehash = require('eth-ens-namehash');

contract('ETHRegistrar', function (accounts) {

    let ens;
    let interimRegistrar;

    before(async () => {
        ens = await ENS.new();
        interimRegistrar = await InterimRegistrar.new(ens.address, namehash.hash('eth'), 0);
        await ens.setSubnodeOwner('0x0', web3Utils.sha3('eth'), interimRegistrar.address);
    });

    it('should allow ownership transfers', async () => {
    });
});
