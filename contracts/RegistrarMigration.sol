pragma solidity ^0.5.0;

import "@ensdomains/ens/contracts/ENS.sol";
import "./BaseRegistrarImplementation.sol";

contract RegistrarMigration {
    using SafeMath for uint;

    BaseRegistrarImplementation public oldRegistrar;
    BaseRegistrarImplementation public newRegistrar;
    ENS public oldENS;
    ENS public newENS;
    bytes32 public baseNode;

    constructor(BaseRegistrarImplementation _old, BaseRegistrarImplementation _new) public {
        oldRegistrar = _old;
        oldENS = _old.ens();
        baseNode = _old.baseNode();

        newRegistrar = _new;
        newENS = _new.ens();
        require(_new.baseNode() == baseNode);
    }

    function migrate(uint256 tokenId) public {
        address registrant = oldRegistrar.ownerOf(tokenId);
        bytes32 node = keccak256(abi.encodePacked(baseNode, bytes32(tokenId)));
        address controller = oldENS.owner(node);

        if(hasCode(controller)) {
            // For names controlled by a contract, only migrate over the registration
            newRegistrar.registerOnly(tokenId, registrant, oldRegistrar.nameExpires(tokenId).sub(now));
        } else {
            // Register the name on the new registry with the same expiry time.
            newRegistrar.register(tokenId, address(this), oldRegistrar.nameExpires(tokenId).sub(now));

            // Copy over resolver, TTL and owner to the new registry.
            address resolver = oldENS.resolver(node);
            if(resolver != address(0)) {
                newENS.setResolver(node, resolver);
            }

            uint64 ttl = oldENS.ttl(node);
            if(ttl != 0) {
                newENS.setTTL(node, ttl);
            }

            if(controller != address(0)) {
                newENS.setOwner(node, controller);
            } else {
                newENS.setOwner(node, address(this));
            }

            // Transfer the registration to the registrant.
            newRegistrar.transferFrom(address(this), registrant, tokenId);

            // Replace ownership on the old registry so it can't be updated any further.
            oldENS.setSubnodeOwner(baseNode, bytes32(tokenId), address(this));
        }
    }

    function migrateAll(uint256[] calldata tokenIds) external {
        for(uint i = 0; i < tokenIds.length; i++) {
            migrate(tokenIds[i]);
        }
    }

    function hasCode(address addr) private view returns(bool ret) {
        assembly {
            ret := not(not(extcodesize(addr)))
        }
    }
}
