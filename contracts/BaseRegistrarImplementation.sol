pragma solidity ^0.5.0;

import "@ensdomains/ens/contracts/ENS.sol";
import "@ensdomains/ens/contracts/Registrar.sol";
import "@ensdomains/ens/contracts/HashRegistrar.sol";
import "./BaseRegistrar.sol";

contract BaseRegistrarImplementation is BaseRegistrar {
    constructor(ENS _ens, bytes32 _baseNode, uint _transferPeriodEnds) public {
        ens = _ens;
        baseNode = _baseNode;
        previousRegistrar = HashRegistrar(ens.owner(baseNode));
        transferPeriodEnds = _transferPeriodEnds;
    }

    modifier live {
        require(ens.owner(baseNode) == address(this));
        _;
    }

    modifier owns(bytes32 label) {
        require(registrations[label].expiresAt > now);
        require(registrations[label].owner == msg.sender);
        _;
    }

    modifier onlyController {
        require(controllers[msg.sender]);
        _;
    }

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    // Revoke controller permission for an address.
    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    // Returns the owner of the specified label hash.
    function nameOwner(bytes32 label) external view returns(address) {
        return registrations[label].owner;
    }

    // Returns the expiration timestamp of the specified label hash.
    function nameExpires(bytes32 label) external view returns(uint) {
        return registrations[label].expiresAt;
    }

    // Returns true iff the specified name is available for registration.
    function available(bytes32 label) public view returns(bool) {
        // Not available if it's registered here.
        if(registrations[label].expiresAt + GRACE_PERIOD >= now) {
            return false;
        }
        // Available if we're past the transfer period, or the name isn't
        // registered in the legacy registrar.
        return now > transferPeriodEnds || previousRegistrar.state(label) == Registrar.Mode.Open;
    }

    /**
     * @dev Register a name.
     */
    function register(bytes32 label, address owner, uint duration) external live onlyController returns(uint) {
        require(available(label));

        registrations[label] = Registration(owner, now + duration);
        ens.setSubnodeOwner(baseNode, label, owner);
        emit NameRegistered(label, owner, now + duration);
        return now + duration;
    }

    function renew(bytes32 label, uint duration) external live onlyController returns(uint) {
        require(!available(label));

        registrations[label].expiresAt += duration;
        emit NameRenewed(label, registrations[label].expiresAt);
        return registrations[label].expiresAt;
    }

    /**
     * @dev Transfer ownership of a name to another account.
     */
    function transfer(bytes32 label, address newOwner) external owns(label) {
        emit NameTransferred(label, msg.sender, newOwner);
        registrations[label].owner = newOwner;
    }

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(bytes32 label) external owns(label) live {
        ens.setSubnodeOwner(baseNode, label, registrations[label].owner);
    }

    /**
     * @dev Transfers a registration from the initial registrar.
     * This function is called by the initial registrar when a user calls `transferRegistrars`.
     */
    function acceptRegistrarTransfer(bytes32 label, Deed deed, uint) external {
        require(msg.sender == address(previousRegistrar));
        require(registrations[label].owner == address(0));
        require(transferPeriodEnds > now);

        address owner = deed.owner();

        // Destroy the deed and transfer the funds back to the registrant.
        deed.closeDeed(1000);

        // Register the name
        emit NameMigrated(label, owner, transferPeriodEnds);
        emit NameRegistered(label, owner, transferPeriodEnds);
        registrations[label] = Registration(owner, transferPeriodEnds);
        ens.setSubnodeOwner(baseNode, label, owner);
    }
}
